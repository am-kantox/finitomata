defmodule Finitomata.Flow do
  @moduledoc """
  The basic “brick” to build forks in top-level `Finitomata` instances.

  ## Definition Syntax

  To construct the `Flow`, one should use the declarative map with events and states, as a string.

  ```elixir
  %{
    "start" => %{valid_states: [:new], handler: &Foo.Bar.recipient_flow_name/3, initial: "✓"},
    "submit_name" => %{valid_states: [:started, :phone_number_submitted], handler: &submit_name/3},
    "submit_phone_number" => %{valid_states: [:started, :name_submitted], handler: &sumbit_phone/3},
    "commit" => %{valid_states: [:submit_name, :submit_phone_number], handler: &commit/3, final: "✓"}
  }
  ```

  and pass it to the `use Finitomata.Flow` as shown below. The declaration might be loaded from a file,
    or passed directly as a string.

  ```elixir
  defmodule OnboardingFlow do
    @moduledoc false
    use Finitomata.Flow, flow: "priv/flows/onboarding.flow"
  end
  ```

  ## Using with _FSM_

  The FSM wanting to use the flow, must use `forks: [state: [event: FlowImplModule, …]]` option in a call to
    `use Finitomata`

  ```elixir
    use Finitomata, fsm: @fsm, …, forks: [started: [to_onboarded: OnboardingFlow]]
  ```

  The compilation checks for both validity and consistency would be performed for `OnboardingFlow`.

  Once the main FSM enters the state marked as `forks:` (`:started` in this particular example,)
  the FSM with the name `{:fork, :started, MainFsmName}` will be launched and the main FSM would
  wait for it to be finished. Upon termination, the flow FSM would send `:to_onboarded` event to
  the main FSM, enforcing it to move to the next state.

  One might specify several `Flow`s for the same event and state. In that case, `c:Finitomata.on_fork/2`
  event must be implemented to decide what `Flow` to start in runtime.

  ```elixir
    use Finitomata, fsm: @fsm, …, forks: [s1: [evt: Flow1, evt: Flow2]]

    […]

    @impl Finitomata
    def on_fork(:s1, %{} = state) do
      if state.simple_flow?,
        do: {:ok, Flow1},
        else: {:ok, Flow2}
    end
  ```

  ## `Flow` management

  `Flow`’s API is dedicated to the `event/4` function. To start a transition
    for the `FLow`, one should call somewhat along the following lines.

  ```elixir
  Finitomata.Flow.event({:fork, :s1, "MainFSM"}, :submit_name, :commit)
  ```

  The above will transition the `Flow` to the final state, terminating the `Flow`
    and sending `:to_onboarded` event to the main _FSM_.
  """

  alias Finitomata.{State, Transition}

  @start_handler :on_flow_initialization
  @start_state "finitomata__flowing"
  @end_state "finitomata__flowed"
  @start_event "finitomata__flow__initialize!"
  @back_event "finitomata__back"

  @typedoc "The result of event processing"
  @type event_resolution :: {:ok, term()} | :fsm_gone | {:error, Finitomata.State.payload()}

  @typedoc "The option to be passed to control the event behaviour"
  @type event_option :: {:skip_handlers?, boolean()}

  @typedoc "The options to be passed to control the event behaviour"
  @type event_options :: [event_option()]

  @doc "Performs the transition to the predefined state, awaits for a result"
  @spec event(
          {Finitomata.id(), Finitomata.fsm_name()} | Finitomata.fsm_name(),
          Transition.event(),
          term()
        ) :: event_resolution()
  def event(id_name, event, payload \\ nil)

  def event({id, name}, event, payload) do
    :ok = Finitomata.transition(id, name, {event, payload})

    case Finitomata.state(id, name, :payload) do
      nil ->
        :fsm_gone

      %{history: %{steps: [{_state, ^event, result} | _]}} ->
        {:ok, result}

      %{history: %{steps: steps, current: current}}
      when event == unquote(:"#{@back_event}") ->
        case Enum.at(steps, current) do
          nil -> {:error, :unknown_step}
          {_state, _event, result} -> {:ok, result}
        end

      payload ->
        {:error, payload}
    end
  end

  def event(name, event, payload), do: event({nil, name}, event, payload)

  @doc "Performs the transition to the desired state, awaits for a result"
  @spec event(
          {Finitomata.id(), Finitomata.fsm_name()} | Finitomata.fsm_name(),
          Transition.event(),
          Transition.state(),
          term(),
          event_options()
        ) :: event_resolution()
  def event(id_name, event, target_state, payload, options \\ [])

  def event({id, name}, event, target_state, payload, options) do
    :ok = Finitomata.transition(id, name, {event, {target_state, payload, options}})

    case Finitomata.state(id, name, :payload) do
      nil ->
        :fsm_gone

      %{history: %{steps: [{_state, ^event, result} | _]}} ->
        {:ok, result}

      %{history: %{steps: steps, current: current}}
      when event == unquote(:"#{@back_event}") ->
        case Enum.at(steps, current) do
          nil -> {:error, :unknown_step}
          {_state, _event, result} -> {:ok, result}
        end

      payload ->
        {:error, payload}
    end
  end

  def event(name, event, target_state, payload, options),
    do: event({nil, name}, event, target_state, payload, options)

  @doc """
  Fast-forwards the flow into one of the reachable states.
  """
  @spec fast_forward(
          {Finitomata.id(), Finitomata.fsm_name()} | Finitomata.fsm_name(),
          target :: Transition.state() | [Transition.state()] | Transition.Path.t(),
          options :: event_options()
        ) :: {:ok, [event_resolution()]} | {:fsm_gone, [event_resolution()]} | {:error, term()}
  def fast_forward(id_name, target, options \\ [])

  def fast_forward({id, name}, %Transition.Path{path: path} = _target, options) do
    Enum.reduce_while(path, {:ok, []}, fn
      {event, state}, {:ok, acc} ->
        case event({id, name}, event, state, nil, options) do
          {:ok, term} -> {:cont, {:ok, acc ++ [{event, {state, term}}]}}
          :fsm_gone -> {:halt, {:fsm_gone, acc}}
          {:error, reason} -> {:halt, {:error, {reason, acc}}}
        end
    end)
  end

  def fast_forward({id, name}, target_states, options) when is_list(target_states) do
    Enum.reduce_while(target_states, {:ok, []}, fn
      target_state, {:ok, acc} ->
        case fast_forward({id, name}, target_state, options) do
          {:ok, results} -> {:cont, {:ok, acc ++ results}}
          {:fsm_gone, inner_acc} -> {:halt, {:fsm_gone, acc ++ inner_acc}}
          {:error, {reason, inner_acc}} -> {:halt, {:error, {reason, acc ++ inner_acc}}}
        end
    end)
  end

  def fast_forward({id, name}, target_state, options) when is_atom(target_state) do
    with {:ok, %{module: module}} <- id |> Finitomata.all() |> Map.fetch(name),
         %State{} = state <- Finitomata.state(id, name),
         [%Transition.Path{} = path | _] <-
           Transition.shortest_paths(
             :states,
             module.__config__(:fsm),
             state.current,
             target_state,
             false
           ) do
      fast_forward({id, name}, path, options)
    else
      [] -> {:ok, []}
      not_ok -> {:error, {:ffwd_flow, not_ok}}
    end
  end

  def fast_forward(name, target_state, options),
    do: fast_forward({nil, name}, target_state, options)

  @doc false
  defmacro __using__(opts \\ []) do
    {flow, opts} = Keyword.pop!(opts, :flow)
    {flow_opts, opts} = Keyword.pop(opts, :flow_opts, [])

    case Finitomata.Flow.load_map(flow, flow_opts) do
      {:ok, {fsm, states}} ->
        finitomata_options =
          Keyword.merge(opts, fsm: fsm, auto_terminate: true, cache_state: false)

        # AST for the internal `defp` functions, performing the actual work
        utility_ast =
          quote generated: true, location: :keep do
            defp do_transition_step(current, event, target_state, result, state) do
              history = %{
                steps: [
                  {current, event, result}
                  | Enum.slice(
                      state.history.steps,
                      state.history.current,
                      length(state.history.steps)
                    )
                ],
                current: 0
              }

              steps_left = Finitomata.Transition.steps_handled(__config__(:fsm), target_state, :*)
              steps_passed = length(history.steps) - 1

              {:ok, target_state,
               %{
                 state
                 | history: history,
                   steps: %{passed: steps_passed, left: steps_left}
               }}
            end
          end

        # AST for the generated handlers,
        #   returning `{:ok, {unquote_splicing(args)}}` as the result
        #   and printing a warning
        internal_calls_ast =
          states
          |> Enum.map(&elem(&1, 1))
          |> Enum.uniq_by(&elem(&1, 0))
          |> Enum.flat_map(fn
            {{_, _} = _external, _arity} ->
              []

            {_fun, arity} when is_binary(arity) ->
              []

            {fun, arity} ->
              args = Macro.generate_arguments(arity, __CALLER__.module)
              args_string = Enum.map_join(args, ", ", &elem(&1, 0))

              [
                quote generated: true, location: :keep do
                  def unquote(:"#{fun}")(unquote_splicing(args)) do
                    require Logger

                    Logger.warning("""
                      handler #{unquote(fun)}/#{unquote(arity)} has been declared in the flow definition (module #{inspect(__MODULE__)}).

                      We will inject a default implementation for now:

                        def #{unquote(fun)}(#{unquote(args_string)}) do
                          {:ok, {#{unquote(args_string)}}}
                        end

                    You can copy the implementation above or define your own that actually handles the flow step.
                    """)

                    {:ok, {unquote_splicing(args)}}
                  end

                  defoverridable [{unquote(:"#{fun}"), unquote(arity)}]
                end
              ]
          end)

        # AST for the `on_transition/4` handler for `:finitomata_back` event
        back_handler_ast =
          quote generated: true, location: :keep do
            @doc false
            @impl Finitomata
            def on_transition(current_state, unquote(:"#{@back_event}"), _payload, state) do
              case Enum.at(state.history.steps, state.history.current) do
                nil ->
                  {:error, :no_previous_state}

                {prev, _event, _result} ->
                  current_step = state.history.current + 1
                  steps_left = Finitomata.Transition.steps_handled(__config__(:fsm), prev, :*)
                  steps_passed = length(state.history.steps) - current_step

                  if Map.fetch!(state.steps, :passed) != steps_passed,
                    do: Logger.warning("[FINITOMATA] Internal error: diverged steps count")

                  {:ok, prev,
                   %{
                     state
                     | steps: %{passed: steps_passed, left: steps_left},
                       history: %{current: current_step, steps: state.history.steps}
                   }}
              end
            end

            def on_transition(unquote(:"#{@start_state}"), unquote(:"#{@start_event}"), _, state) do
              case unquote(@start_handler)(state) do
                :ok ->
                  Finitomata.Transition.guess_next_state(
                    __config__(:fsm),
                    unquote(:"#{@start_state}"),
                    unquote(:"#{@start_event}"),
                    state
                  )

                {:ok, state} ->
                  Finitomata.Transition.guess_next_state(
                    __config__(:fsm),
                    unquote(:"#{@start_state}"),
                    unquote(:"#{@start_event}"),
                    state
                  )

                {:error, error} ->
                  {:error, error}
              end
            end
          end

        # AST for `on_transition/4` handlers
        # According to the arity of the handler, it’ll receive:
        # ① `{payload, state}` tuple
        # ② `payload, object`
        # ③ `payload, id, object`

        handlers_ast =
          for {%{state: state, event: event}, {fun, arity}} <- states do
            state = String.to_atom(state)
            event = String.to_atom(event)

            case {fun, arity} do
              {_, arity} when is_binary(arity) ->
                quote generated: true, location: :keep do
                  def on_transition(
                        unquote(state),
                        unquote(event),
                        {target_state, _payload, options},
                        state
                      ) do
                    skip_handlers? = Keyword.get(options, :skip_handlers?, false)
                    result = if skip_handlers?, do: :skipped, else: unquote(@start_handler)(state)

                    do_transition_step(
                      unquote(state),
                      unquote(event),
                      target_state,
                      result,
                      state
                    )
                  end
                end

              {{mod, fun}, 1} ->
                quote generated: true, location: :keep do
                  def on_transition(
                        unquote(state),
                        unquote(event),
                        {target_state, payload, options},
                        state
                      ) do
                    skip_handlers? = Keyword.get(options, :skip_handlers?, false)

                    result =
                      if skip_handlers?,
                        do: :skipped,
                        else:
                          Function.capture(unquote(mod), unquote(fun), unquote(arity)).(
                            {payload, state}
                          )

                    do_transition_step(
                      unquote(state),
                      unquote(event),
                      target_state,
                      result,
                      state
                    )
                  end
                end

              {{mod, fun}, 2} ->
                quote generated: true, location: :keep do
                  def on_transition(
                        unquote(state),
                        unquote(event),
                        {target_state, payload, options},
                        state
                      ) do
                    skip_handlers? = Keyword.get(options, :skip_handlers?, false)

                    result =
                      if skip_handlers?,
                        do: :skipped,
                        else:
                          Function.capture(unquote(mod), unquote(fun), unquote(arity)).(
                            payload,
                            state.object
                          )

                    do_transition_step(
                      unquote(state),
                      unquote(event),
                      target_state,
                      result,
                      state
                    )
                  end
                end

              {{mod, fun}, 3} ->
                quote generated: true, location: :keep do
                  def on_transition(
                        unquote(state),
                        unquote(event),
                        {target_state, payload, options},
                        state
                      ) do
                    skip_handlers? = Keyword.get(options, :skip_handlers?, false)

                    result =
                      if skip_handlers?,
                        do: :skipped,
                        else:
                          Function.capture(unquote(mod), unquote(fun), unquote(arity)).(
                            payload,
                            state.id,
                            state.object
                          )

                    do_transition_step(
                      unquote(state),
                      unquote(event),
                      target_state,
                      result,
                      state
                    )
                  end
                end

              {fun, 3} when is_atom(fun) ->
                quote generated: true, location: :keep do
                  def on_transition(
                        unquote(state),
                        unquote(event),
                        {target_state, payload, options},
                        state
                      ) do
                    skip_handlers? = Keyword.get(options, :skip_handlers?, false)

                    result =
                      if skip_handlers?,
                        do: :skipped,
                        else: unquote(:"#{fun}")(payload, state.id, state.object)

                    do_transition_step(
                      unquote(state),
                      unquote(event),
                      target_state,
                      result,
                      state
                    )
                  end
                end
            end
          end ++
            [
              # AST to carry all the default implementation for transitions where
              #   handlers are not needed/defined (e. g. for `:__start__` and other
              #   internal transitions)
              quote generated: true, location: :keep do
                def on_transition(current, event, payload, state) do
                  :fsm
                  |> __config__()
                  |> Finitomata.Transition.guess_next_state(current, event, state)
                  |> case do
                    {:ok, flow_state, ^state} when flow_state in @finitomata_flow_states ->
                      on_transition(current, event, {flow_state, payload, []}, state)

                    {:ok, target_state, ^state} ->
                      do_transition_step(current, event, target_state, :ok, state)

                    errored ->
                      errored
                  end
                end
              end
            ]

        handlers_ast = [back_handler_ast | handlers_ast]

        flow_states =
          states
          |> Enum.map(&elem(&1, 0))
          |> Enum.map(& &1.state)
          |> Enum.uniq()
          |> Enum.map(&String.to_atom/1)
          |> Kernel.--([:"#{@start_state}"])
          |> Kernel.++([:"#{@end_state}"])

        # AST for the main stuff, like declaring the `Finitomata` using and stuff
        main_ast =
          quote generated: true, location: :keep do
            use Finitomata, unquote(finitomata_options)
            @finitomata_flow_states unquote(flow_states)

            @impl Finitomata
            def on_terminate(%Finitomata.State{
                  payload: %{owner: %{id: id, name: name, event: event}} = payload
                }) do
              Finitomata.transition(id, name, {event, payload})
            end

            @doc """
            The initialization function that will be called before the `Flow` enters the initial state
            """
            def unquote(@start_handler)(state) do
              {:ok, state}
            end

            defoverridable [{unquote(@start_handler), 1}]
          end

        [main_ast, utility_ast, internal_calls_ast | handlers_ast]

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
  @doc false
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
                  # aliases |> Module.concat() |> inspect() |> Kernel.<>(".#{remote}")
                  {Module.concat(aliases), remote}

                {local, _, _} when is_atom(local) ->
                  local
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
                  [_ | _] = states ->
                    {Map.put(
                       states_acc,
                       @start_state,
                       Enum.map(states, &{@start_event, @start_handler, &1})
                     ), states ++ initial_state}

                  _ ->
                    raise CompileError,
                      description: """
                        Starting event must have at least one target state.
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
        [state] ->
          [@start_state, @end_state, state]

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
