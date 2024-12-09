defmodule Finitomata.Flow do
  @moduledoc """
  The basic “brick” to build forks in top-level `Finitomata` instances
  """

  alias Finitomata.Transition

  @start_state "finitomata_flowing"
  @start_event "finitomata_flow_initialize!"
  @end_state "finitomata_flowed"
  @back_event "finitomata_back"

  @doc false
  defmacro __using__(opts \\ []) do
    {flow, opts} = Keyword.pop!(opts, :flow)
    {flow_opts, opts} = Keyword.pop(opts, :flow_opts, [])

    case Finitomata.Flow.load_map(flow, flow_opts) do
      {:ok, {fsm, states}} ->
        finitomata_options = Keyword.merge(opts, fsm: fsm, auto_terminate: true)

        quote generated: true, location: :keep do
          use Finitomata, unquote(finitomata_options)

          def on_flow_initialization(state) do
            {:ok, state}
          end
        end

      {:error, {_meta, message, dump}} ->
        raise CompileError, description: message <> dump
    end
  end

  @typedoc "The expected flow step to configure `Finitomata.Flow`"
  @type flow_step :: %{
          initial: boolean() | binary(),
          final: boolean() | binary(),
          valid_states: [Transition.state()],
          target_states: [Transition.state()],
          handler: (... -> term())
        }
  @typedoc "The expected map to configure `Finitomata.Flow`"
  @type flow_map :: %{
          optional(binary()) => flow_step()
        }

  @spec load_map(String.t(), keyword()) ::
          {:ok,
           {binary(),
            %{
              optional(%{state: binary(), event: binary()}) =>
                {binary(), non_neg_integer() | binary()}
            }}}
          | {:error, {keyword(), String.t(), String.t()}}
  def load_map(string, opts) when is_binary(string) do
    string = if File.exists?(string), do: File.read!(string), else: string

    case Code.string_to_quoted(string) do
      {:ok, {:%{}, _, ast}} -> {:ok, do_parse_ast(ast, opts)}
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
  @spec do_parse_ast(Macro.t(), keyword()) ::
          {binary(),
           %{
             optional(%{state: binary(), event: binary()}) =>
               {binary(), non_neg_integer() | binary()}
           }}
  defp do_parse_ast(kvs, opts) when is_list(kvs) do
    {arity, []} = Keyword.pop(opts, :arity, 3)

    {_ast, {states_acc, events_acc, initial_state}} =
      Macro.postwalk(kvs, {%{}, %{}, []}, fn
        {name, {:%{}, _meta, cfg}} = ast, {states_acc, events_acc, initial_state} ->
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

            {states_acc, initial_state} =
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
                    {Map.put(states_acc, @start_state, [
                       {@start_event, "on_flow_initialization", state}
                     ]), [state | initial_state]}

                  _ ->
                    raise CompileError,
                      description: """
                        Starting event cannot have more than one target state.
                        Found: #{inspect(states)}
                      """
                end
              else
                {states_acc, initial_state}
              end

            events_acc = Map.put(events_acc, name, target_states)

            {ast, {states_acc, events_acc, initial_state}}
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

    no_back_states =
      case initial_state do
        [_] ->
          [@start_state, @end_state]

        other ->
          raise CompileError,
            description:
              "Flow description must have exactly one initial state, marked with `initial: true`, got: " <>
                inspect(other)
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
        target_states = Map.get(events_acc, event, states)

        target_state =
          case event do
            @start_event -> arity
            _ -> target_states
          end

        with_back_states =
          if state in no_back_states do
            [{state, event, target_state}]
          else
            [
              {state, event, target_state}
              | Enum.map(
                  target_states -- [state | no_back_states],
                  &{&1, @back_event, state}
                )
            ]
          end

        {with_back_states, {state, event, handler, arity}}
      end
      |> Enum.reduce({[], %{}}, fn
        {transitions, {state, event, handler, arity}}, {mermaid, handlers} ->
          {transitions ++ mermaid,
           Map.put(handlers, %{state: state, event: event}, {handler, arity})}
      end)

    mermaid =
      mermaid
      |> Enum.uniq()
      |> Enum.group_by(
        fn {from, event, _to} -> {from, event} end,
        fn {_from, _event, to} -> to end
      )
      |> Enum.map(fn {{from, event}, tos} ->
        ~s[#{from} --> |#{event}| #{tos |> List.flatten() |> Enum.join(",")}]
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    {mermaid, handlers}
  end
end
