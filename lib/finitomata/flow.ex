defmodule Finitomata.Flow do
  @moduledoc """
  The basic “brick” to build forks in top-level `Finitomata` instances
  """

  @doc false
  defmacro __using__(opts \\ []) do
    {flow, opts} = Keyword.pop!(opts, :flow)

    quote bind_quoted: [opts: opts, flow: Macro.escape(flow)], generated: true, location: :keep do
      {fsm, states} = Finitomata.Flow.load_map(flow)

      @finitomata_options Keyword.merge(opts, fsm: fsm, auto_terminate: true)

      use Finitomata, fsm: fsm, auto_terminate: true

      def on_flow_initialization(state) do
        {:ok, state}
      end
    end
  end

  @start_state "finitomata_flowing"
  @start_event "finitomata_flow_initialize!"
  @end_state "finitomata_flowed"

  @typedoc "The expected map to configure `Finitomata.Flow`"
  @type flow_map :: %{
          valid_states: [atom()],
          handler: (... -> term())
        }

  @spec load_map(String.t()) :: {:ok, flow_map()} | {:error, {keyword(), String.t(), String.t()}}
  def load_map(string) when is_binary(string) do
    string = if File.exists?(string), do: File.read!(string), else: string

    case Code.string_to_quoted(string) do
      {:ok, {:%{}, _, ast}} -> do_parse_ast(ast)
      {:ok, term} -> {:error, {[line: 1, column: 1], "not a map: ", inspect(term)}}
      {:error, error} -> {:error, error}
    end
  end

  # [
  #   {"start",
  #    {:%{}, [line: 2],
  #     [
  #       valid_states: [:new],
  #       handler: {:&, [line: 2],
  #        [{:/, [line: 2], [{:recipient_flow_name, [line: 2], nil}, 3]}]}
  #     ]}},
  defp do_parse_ast(kvs, opts \\ []) when is_list(kvs) do
    {arity, []} = Keyword.pop(opts, :arity, 3)

    {_ast, {states_acc, events_acc}} =
      Macro.postwalk(kvs, {%{}, %{}}, fn
        {name, {:%{}, _meta, cfg}} = ast, {states_acc, events_acc} ->
          with {:valid_states, {[_ | _] = states, cfg}} <-
                 {:valid_states, Keyword.pop(cfg, :valid_states, [])},
               {:initial, {initial?, cfg}} <- {:initial, Keyword.pop(cfg, :initial)},
               {:final, {final?, cfg}} <- {:final, Keyword.pop(cfg, :final)},
               {:target_states, {target_states, cfg}} <-
                 {:target_states, Keyword.pop(cfg, :target_states)},
               {:handler,
                {{:&, _handler_meta, [{:/, _inner_handler_meta, [fun, ^arity]}]} = _handler, _cfg}} <-
                 {:handler, Keyword.pop(cfg, :handler)} do
            initial? = initial? in [true, "✓"]
            final? = final? in [true, "✓"]
            states = Enum.map(states, &to_string/1)

            fun =
              case fun do
                {{:., _, [{:__aliases__, _, aliases}, remote]}, _, _} ->
                  aliases |> Module.concat() |> inspect() |> Kernel.<>(".#{remote}")

                {local, _, _} when is_atom(local) ->
                  to_string(local)
              end

            states_acc =
              Enum.reduce(
                states,
                states_acc,
                &Map.update(&2, to_string(&1), [{name, fun, arity}], fn handlers ->
                  [{name, fun, arity} | handlers]
                end)
              )

            if final? and target_states != [] do
              raise CompileError,
                description:
                  "Inconsistent description: `final` transition cannot have target states"
            end

            states_acc =
              if initial? do
                if Map.has_key?(states_acc, @start_state) do
                  raise CompileError,
                    description: """
                      Flow description cannot have more than one initial state.
                      Found: #{states_acc |> Map.fetch!(@start_state) |> hd() |> elem(0)}, #{name}
                    """
                end

                case states do
                  [state] ->
                    Map.put(states_acc, @start_state, [
                      {@start_event, "on_flow_initialization", state}
                    ])

                  _ ->
                    raise CompileError,
                      description: """
                        Starting event cannot have more than one target state.
                        Found: #{inspect(states)}
                      """
                end
              else
                states_acc
              end

            events_acc = Map.put(events_acc, name, target_states)

            {ast, {states_acc, events_acc}}
          end

        ast, acc ->
          {ast, acc}
      end)

    states = states_acc |> Map.keys() |> Kernel.--([@start_state])

    if not Map.has_key?(states_acc, @start_state) do
      raise CompileError,
        description:
          "Flow description must have exactly one initial state, marked with `initial: true`"
    end

    events_acc =
      Map.new(events_acc, fn
        {k, nil} -> {k, states}
        {k, []} -> {k, [@end_state]}
        {k, [_ | _] = v} -> {k, v}
      end)

    {mermaid, handlers} =
      for {state, event_handlers} <- states_acc,
          {event, handler, arity} <- event_handlers do
        target_state =
          case event do
            @start_event -> arity
            _ -> events_acc |> Map.get(event, states) |> Enum.join(",")
          end

        {"#{state} --> |#{event}| #{target_state}", {state, event, handler, arity}}
      end
      |> Enum.reduce({[], %{}}, fn
        {transition, {state, event, handler, arity}}, {mermaid, handlers} ->
          {[transition | mermaid],
           Map.put(handlers, %{state: state, event: event}, {handler, arity})}
      end)

    {mermaid |> Enum.reverse() |> Enum.join("\n"), handlers}
  end
end
