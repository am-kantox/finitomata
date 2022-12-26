# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Finitomata do
  @doc false
  def module?(value) do
    case Code.ensure_compiled(value) do
      {:module, ^value} ->
        {:ok, value}

      {:error, error} ->
        {:error, "Cannot find the requested module ‘" <> inspect(value) <> "’ (#{error})"}
    end
  end

  using_schema = [
    fsm: [
      required: true,
      type: :string,
      doc: "The FSM declaration with the syntax defined by `syntax` option."
    ],
    syntax: [
      required: false,
      type: {:custom, Finitomata, :module?, []},
      default: Finitomata.Mermaid,
      doc: "The FSM dialect parser to convert the declaration to internal FSM representation."
    ],
    impl_for: [
      required: false,
      type: {:or, [{:in, [:all, :none]}, :atom, {:list, :atom}]},
      default: :all,
      doc: "The list of transitions to inject default implementation for."
    ],
    timer: [
      required: false,
      type: :pos_integer,
      default: 5_000,
      doc: "The interval to call `on_timer/2` recurrent event."
    ],
    auto_terminate: [
      required: false,
      type: {:or, [:boolean, :atom, {:list, :atom}]},
      default: false,
      doc: "When `true`, the transition to the end state is initiated automatically."
    ],
    ensure_entry: [
      required: false,
      type: {:or, [{:list, :atom}, :boolean]},
      default: [],
      doc: "The list of states to retry transition to until succeeded."
    ],
    shutdown: [
      required: false,
      type: :pos_integer,
      default: 5_000,
      doc: "The shutdown interval for the `GenServer` behind the FSM."
    ],
    persistency: [
      required: false,
      type: {:or, [{:in, [nil]}, {:custom, Finitomata, :module?, []}]},
      default: nil,
      doc:
        "The implementation of `Finitomata.Persistency` behaviour to backup FSM with a persistent storage."
    ]
  ]

  @using_schema NimbleOptions.new!(using_schema)

  doc_options = """
  ## Options to `use Finitomata`

  #{NimbleOptions.docs(@using_schema)}
  """

  doc_readme = "README.md" |> File.read!() |> String.split("\n---") |> Enum.at(1)

  @moduledoc doc_readme <> "\n" <> doc_options

  require Logger

  use Boundary,
    top_level?: true,
    deps: [],
    exports: [Hook, Mix.Events, State, Supervisor, Transition]

  alias Finitomata.Transition

  @typedoc "The payload that can be passed to each call to `transition/3`"
  @type event_payload :: any()

  @typedoc "The name of the FSM (might be any term, but it must be unique)"
  @type fsm_name :: any()

  @typedoc "The resolution of transition, when `{:error, _}` tuple, the transition is aborted"
  @type transition_resolution ::
          {:ok, Transition.state(), Finitomata.State.payload()} | {:error, any()}

  defmodule State do
    @moduledoc """
    Carries the state of the FSM.
    """

    alias Finitomata.Transition

    @typedoc "The payload that has been passed to the FSM instance on startup"
    @type payload :: any()

    @typedoc "The map that holds last error which happened on transition (at given state and event)."
    @type last_error ::
            %{state: Transition.state(), event: Transition.event(), error: any()} | nil

    @typedoc "The internal representation of the FSM state"
    @type t :: %{
            __struct__: State,
            name: Finitomata.fsm_name(),
            current: Transition.state(),
            payload: payload(),
            timer: non_neg_integer(),
            history: [Transition.state()],
            last_error: last_error()
          }
    defstruct name: nil, payload: %{}, current: :*, timer: false, history: [], last_error: nil
  end

  @doc """
  This callback will be called from each transition processor.
  """
  @callback on_transition(
              Transition.state(),
              Transition.event(),
              event_payload(),
              State.payload()
            ) :: transition_resolution()

  @doc """
  This callback will be called if the transition failed to complete to allow
  the consumer to take an action upon failure.
  """
  @callback on_failure(Transition.event(), event_payload(), State.t()) :: :ok

  @doc """
  This callback will be called on entering the state.
  """
  @callback on_enter(Transition.state(), State.t()) :: :ok

  @doc """
  This callback will be called on exiting the state.
  """
  @callback on_exit(Transition.state(), State.t()) :: :ok

  @doc """
  This callback will be called on transition to the final state to allow
  the consumer to perform some cleanup, or like.
  """
  @callback on_terminate(State.t()) :: :ok

  @doc """
  This callback will be called recurrently if `timer: pos_integer()`
    option has been given to `use Finitomata`.
  """
  @callback on_timer(Transition.state(), State.t()) ::
              :ok
              | {:transition, {Transition.event(), event_payload()}, State.payload()}
              | {:transition, Transition.event(), State.payload()}
              | {:reschedule, non_neg_integer()}

  @optional_callbacks on_failure: 3, on_enter: 2, on_exit: 2, on_terminate: 1, on_timer: 2

  @doc """
  Starts the FSM instance.

  The arguments are

  - the implementation of FSM (the module, having `use Finitomata`)
  - the name of the FSM (might be any term, but it must be unique)
  - the payload to be carried in the FSM state during the lifecycle

  The FSM is started supervised.
  """
  @spec start_fsm(module(), any(), any()) :: DynamicSupervisor.on_start_child()
  def start_fsm(impl, name, payload) do
    DynamicSupervisor.start_child(Finitomata.Manager, {impl, name: fqn(name), payload: payload})
  end

  @doc """
  Initiates the transition.

  The arguments are

  - the name of the FSM
  - `{event, event_payload}` tuple; the payload will be passed to the respective
    `on_transition/4` call
  - `delay` (optional) the interval in milliseconds to apply transition after
  """
  @spec transition(fsm_name(), {Transition.event(), State.payload()}, non_neg_integer()) :: :ok
  def transition(target, event_payload, delay \\ 0)

  def transition(target, {event, payload}, 0),
    do: target |> fqn() |> GenServer.cast({event, payload})

  def transition(target, {event, payload}, delay) when is_integer(delay) and delay > 0 do
    fn ->
      Process.sleep(delay)
      target |> fqn() |> GenServer.cast({event, payload})
    end
    |> Task.start()
    |> elem(0)
  end

  @doc """
  The state of the FSM.
  """
  @spec state(fsm_name()) :: State.t()
  def state(target), do: target |> fqn() |> GenServer.call(:state)

  @doc """
  Returns `true` if the transition to the state `state` is possible, `false` otherwise.
  """
  @spec allowed?(fsm_name(), Transition.state()) :: boolean()
  def allowed?(target, state), do: target |> fqn() |> GenServer.call({:allowed?, state})

  @doc """
  Returns `true` if the transition by the event `event` is possible, `false` otherwise.
  """
  @spec responds?(fsm_name(), Transition.event()) :: boolean()
  def responds?(target, event), do: target |> fqn() |> GenServer.call({:responds?, event})

  @doc """
  Returns `true` if the supervision tree is alive, `false` otherwise.
  """
  @spec alive? :: boolean()
  def alive?, do: is_pid(Process.whereis(Registry.Finitomata))

  @doc """
  Returns `true` if the FSM specified is alive, `false` otherwise.
  """
  @spec alive?(fsm_name()) :: boolean()
  def alive?(target), do: target |> fqn() |> GenServer.whereis() |> is_pid()

  @doc false
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(id \\ 0),
    do: Supervisor.child_spec({Finitomata.Supervisor, []}, id: {Finitomata, id})

  @doc false
  @spec start_link(any()) ::
          {:ok, pid} | {:error, {:already_started, pid()} | {:shutdown, term()} | term()}
  def start_link(id \\ 0) do
    Supervisor.start_link([Finitomata.child_spec(id)], strategy: :one_for_one)
  end

  @doc false
  defmacro __using__(opts) when is_list(opts) do
    raise_opts = fn description ->
      [
        file: Path.relative_to_cwd(__CALLER__.file),
        line: __CALLER__.line,
        description: description
      ]
    end

    if not Keyword.keyword?(opts) do
      raise CompileError, raise_opts.("options to `use Finitomata` must be a keyword list")
    end

    ast(opts, @using_schema)
  end

  @doc false
  @doc deprecated: "Use `use fsm: …, syntax: …` instead"
  defmacro __using__({fsm, syntax}), do: ast([fsm: fsm, syntax: syntax], @using_schema)

  @doc false
  @doc deprecated: "Use `use fsm: …, syntax: …` instead"
  defmacro __using__(fsm), do: ast([fsm: fsm], @using_schema)

  @doc false
  defp ast(options, schema) do
    quote location: :keep, generated: true do
      with {:error, ex} <-
             NimbleOptions.validate(unquote(options), unquote(Macro.escape(schema))),
           do: raise(ex)

      require Logger

      alias Finitomata.Transition, as: Transition

      @on_definition Finitomata.Hook
      @before_compile Finitomata.Hook

      syntax =
        Keyword.get(
          unquote(options),
          :syntax,
          Application.compile_env(:finitomata, :syntax, Finitomata.Mermaid)
        )

      shutdown =
        Keyword.get(
          unquote(options),
          :shutdown,
          Application.compile_env(:finitomata, :shutdown, 5_000)
        )

      auto_terminate =
        Keyword.get(
          unquote(options),
          :auto_terminate,
          Application.compile_env(:finitomata, :auto_terminate, false)
        )

      @persistency Keyword.get(
                     unquote(options),
                     :persistency,
                     Application.compile_env(:finitomata, :persistency, nil)
                   )

      use GenServer, restart: :transient, shutdown: shutdown

      impls = ~w|on_transition on_failure on_enter on_exit on_terminate on_timer|a

      impl_for =
        case Keyword.get(unquote(options), :impl_for, :all) do
          :all -> impls
          :none -> []
          transition when is_atom(transition) -> [transition]
          list when is_list(list) -> list
        end

      if impl_for -- impls != [] do
        raise CompileError,
          description:
            "allowed `impl_for:` values are: `:all`, `:none`, or any combination of `#{inspect(impls)}`"
      end

      fsm =
        case syntax.parse(unquote(options[:fsm])) do
          {:ok, result} ->
            result

          {:error, description, snippet, _, {line, column}, _} ->
            raise SyntaxError,
              file: "lib/finitomata.ex",
              line: line,
              column: column,
              description: description,
              snippet: %{content: snippet, offset: 0}

          {:error, error} ->
            raise TokenMissingError,
              description: "description is incomplete, error: #{error}"
        end

      states =
        fsm
        |> Enum.flat_map(&[&1.from, &1.to])
        |> Enum.uniq()

      hard =
        fsm
        |> Transition.determined()
        |> Enum.filter(fn
          {state, :__end__} ->
            case auto_terminate do
              ^state -> true
              true -> true
              list when is_list(list) -> state in list
              _ -> false
            end

          {state, event} ->
            event
            |> to_string()
            |> String.ends_with?("!")
        end)

      soft =
        Enum.filter(fsm, fn
          %Transition{event: event} ->
            event
            |> to_string()
            |> String.ends_with?("?")
        end)

      ensure_entry =
        unquote(options)
        |> Keyword.get(
          :ensure_entry,
          Application.compile_env(:finitomata, :ensure_entry, [])
        )
        |> case do
          list when is_list(list) -> list
          true -> [Transition.entry(fsm)]
          _ -> []
        end

      timer =
        unquote(options)
        |> Keyword.get(:timer)
        |> case do
          value when is_integer(value) and value >= 0 -> value
          true -> Application.compile_env(:finitomata, :timer, 5_000)
          _ -> false
        end

      @__config__ %{
        syntax: syntax,
        fsm: fsm,
        impl_for: impl_for,
        auto_terminate: auto_terminate,
        ensure_entry: ensure_entry,
        states: states,
        hard: hard,
        soft: soft,
        timer: timer
      }
      @__config_soft_events__ Enum.map(soft, & &1.event)
      @__config_hard_states__ Keyword.keys(hard)

      @doc false
      def fsm, do: Map.get(@__config__, :fsm)

      @doc false
      def states(purge_internal \\ false)
      def states(false), do: fsm() |> Enum.flat_map(&[&1.from, &1.to]) |> Enum.uniq()
      def states(true), do: false |> states() |> Kernel.--([:*])

      @doc false
      def events(purge_internal \\ false)
      def events(false), do: fsm() |> Enum.map(& &1.event) |> Enum.uniq()
      def events(true), do: false |> events() |> Kernel.--([:__start__, :__end__])

      @doc false
      def start_link(payload: payload, name: name),
        do: start_link(name: name, payload: payload)

      @doc ~s"""
      Starts an _FSM_ alone with `name` and `payload` given.

      Usually one does not want to call this directly, the most common way would be
      to start a `Finitomata` supervision tree with `Finitomata.Supervisor.start_link/1`
      or even better embed it into the existing supervision tree _and_
      start _FSM_ with `Finitomata.start_fsm/3` passing `#{__MODULE__}` as the first
      parameter.

      FSM representation

      ```#{@__config__[:syntax] |> Module.split() |> List.last() |> Macro.underscore()}
      #{@__config__[:syntax].lint(unquote(options[:fsm]))}
      ```
      """
      case @persistency do
        nil ->
          def start_link(name: name, payload: payload) do
            GenServer.start_link(__MODULE__, %{name: name, payload: payload}, name: name)
          end

        module when is_atom(module) ->
          def start_link(name: name, payload: payload) do
            payload = @persistency.load(name, payload)

            GenServer.start_link(
              __MODULE__,
              %{name: name, payload: payload, loaded?: true},
              name: name
            )
          end
      end

      @doc false
      def start_link(payload),
        do: GenServer.start_link(__MODULE__, %{payload: payload})

      @doc false
      @impl GenServer
      def init(%{payload: payload} = state) do
        if is_integer(@__config__[:timer]) and @__config__[:timer] > 0,
          do: Process.send_after(self(), :on_timer, @__config__[:timer])

        {:ok, %State{name: state.name, timer: @__config__[:timer], payload: payload},
         {:continue,
          {:transition, event_payload({:__start__, Transition.entry(@__config__[:fsm])})}}}
      end

      @doc false
      @impl GenServer
      def handle_call(:state, _from, state), do: {:reply, state, state}

      @doc false
      @impl GenServer
      def handle_call({:allowed?, to}, _from, state),
        do: {:reply, Transition.allowed?(@__config__[:fsm], state.current, to), state}

      @doc false
      @impl GenServer
      def handle_call({:responds?, event}, _from, state),
        do: {:reply, Transition.responds?(@__config__[:fsm], state.current, event), state}

      @doc false
      @impl GenServer
      def handle_cast({event, payload}, state),
        do: {:noreply, state, {:continue, {:transition, {event, payload}}}}

      @doc false
      @impl GenServer
      def handle_continue({:transition, {event, payload}}, state),
        do: transit({event, payload}, state)

      @doc false
      @impl GenServer
      def terminate(reason, state) do
        safe_on_terminate(state)
      end

      @spec history(Transition.state(), [Transition.state()]) :: [Transition.state()]
      defp history(current, history) do
        case history do
          [^current | rest] -> [{current, 2} | rest]
          [{^current, count} | rest] -> [{current, count + 1} | rest]
          _ -> [current | history]
        end
      end

      @spec event_payload(Transition.event() | {Transition.event(), Finitomata.event_payload()}) ::
              {Transition.event(), Finitomata.event_payload()}
      defp event_payload({event, %{} = payload}),
        do: {event, Map.update(payload, :__retries__, 1, &(&1 + 1))}

      defp event_payload({event, payload}),
        do: event_payload({event, %{payload: payload}})

      defp event_payload(event),
        do: event_payload({event, %{}})

      @spec transit({Transition.event(), Finitomata.event_payload()}, State.t()) ::
              {:noreply, State.t()} | {:stop, :normal, State.t()}
      defp transit({event, payload}, state) do
        with {:responds, true} <-
               {:responds, Transition.responds?(@__config__[:fsm], state.current, event)},
             {:on_exit, :ok} <- {:on_exit, safe_on_exit(state.current, state)},
             {:ok, new_current, new_payload} <-
               safe_on_transition(state.name, state.current, event, payload, state.payload),
             {:allowed, true} <-
               {:allowed, Transition.allowed?(@__config__[:fsm], state.current, new_current)},
             new_history = history(state.current, state.history),
             state = %State{
               state
               | payload: new_payload,
                 current: new_current,
                 history: new_history
             },
             {:on_enter, :ok} <- {:on_enter, safe_on_enter(new_current, state)} do
          case new_current do
            :* ->
              {:stop, :normal, state}

            hard when hard in @__config_hard_states__ ->
              {:noreply, state,
               {:continue, {:transition, event_payload(@__config__[:hard][hard])}}}

            _ ->
              {:noreply, state}
          end
        else
          {err, false} ->
            Logger.warn("[⚐⥯] transition not exists or not allowed (:#{err})")
            safe_on_failure(event, payload, state)
            {:noreply, state}

          {err, :ok} ->
            Logger.warn("[⚐⥯] callback failed to return `:ok` (:#{err})")
            safe_on_failure(event, payload, state)
            {:noreply, state}

          err ->
            state = %State{state | last_error: %{state: state.current, event: event, error: err}}

            cond do
              event in @__config_soft_events__ ->
                Logger.debug("[⚐⥯] transition softly failed " <> inspect(err))
                {:noreply, state}

              @__config__[:fsm]
              |> Transition.allowed(state.current, event)
              |> Enum.all?(&(&1 in @__config__[:ensure_entry])) ->
                {:noreply, state, {:continue, {:transition, event_payload({event, payload})}}}

              true ->
                Logger.warn("[⚐⥯] transition failed " <> inspect(err))
                safe_on_failure(event, payload, state)
                {:noreply, state}
            end
        end
      end

      if @__config__[:timer] do
        @impl GenServer
        @doc false
        def handle_info(:on_timer, state) do
          state.current
          |> safe_on_timer(state)
          |> case do
            :ok ->
              {:noreply, state}

            {:transition, {event, event_payload}, state_payload} ->
              transit({event, event_payload}, %State{state | payload: state_payload})

            {:transition, event, state_payload} ->
              transit({event, nil}, %State{state | payload: state_payload})

            {:reschedule, value} when is_integer(value) and value >= 0 ->
              {:noreply, %State{state | timer: value}}

            weird ->
              Logger.warn("[⚑⥯] on_timer returned a garbage " <> inspect(weird))
              {:noreply, state}
          end
          |> tap(fn
            {:noreply, %State{timer: timer}} when is_integer(timer) and timer > 0 ->
              Process.send_after(self(), :on_timer, timer)

            _ ->
              :ok
          end)
        end
      end

      @spec safe_on_transition(
              Finitomata.fsm_name(),
              Transition.state(),
              Transition.event(),
              Finitomata.event_payload(),
              State.payload()
            ) ::
              {:ok, Transition.state(), State.payload()}
              | {:error, any()}
              | {:error, :on_transition_raised}
      defp safe_on_transition(name, current, event, event_payload, state_payload) do
        current
        |> on_transition(event, event_payload, state_payload)
        |> maybe_store(name, current, event, event_payload, state_payload)
      rescue
        err ->
          case err do
            %{__exception__: true} ->
              {ex, st} = Exception.blame(:error, err, __STACKTRACE__)
              Logger.debug(Exception.format(:error, ex, st))
              {:error, Exception.message(err)}

            _ ->
              Logger.warn("[⚑⥯] on_transition raised " <> inspect(err))
              {:error, :on_transition_raised}
          end
      end

      @spec safe_on_failure(Transition.event(), Finitomata.event_payload(), State.t()) :: :ok
      defp safe_on_failure(event, event_payload, state_payload) do
        if function_exported?(__MODULE__, :on_failure, 3) do
          with other when other != :ok <-
                 apply(__MODULE__, :on_failure, [event, event_payload, state_payload]) do
            Logger.info("Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> Logger.warn("[⚑⥯] on_failure raised " <> inspect(err))
      end

      @spec safe_on_enter(Transition.state(), State.t()) :: :ok
      defp safe_on_enter(state, state_payload) do
        if function_exported?(__MODULE__, :on_enter, 2) do
          with other when other != :ok <- apply(__MODULE__, :on_enter, [state, state_payload]) do
            Logger.info("Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> Logger.warn("[⚑⥯] on_enter raised " <> inspect(err))
      end

      @spec safe_on_exit(Transition.state(), State.t()) :: :ok
      defp safe_on_exit(state, state_payload) do
        if function_exported?(__MODULE__, :on_exit, 2) do
          with other when other != :ok <- apply(__MODULE__, :on_exit, [state, state_payload]) do
            Logger.info("Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> Logger.warn("[⚑⥯] on_exit raised " <> inspect(err))
      end

      @spec safe_on_terminate(State.t()) :: :ok
      defp safe_on_terminate(state) do
        if function_exported?(__MODULE__, :on_terminate, 1) do
          with other when other != :ok <- apply(__MODULE__, :on_terminate, [state]) do
            Logger.info("Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> Logger.warn("[⚑⥯] on_terminate raised " <> inspect(err))
      end

      @spec safe_on_timer(Transition.state(), State.t()) ::
              :ok
              | {:transition, {Transition.state(), Finitomata.event_payload()}, State.payload()}
              | {:transition, Transition.state(), State.payload()}
              | {:reschedule, pos_integer()}
      defp safe_on_timer(state, state_payload) do
        if function_exported?(__MODULE__, :on_timer, 2),
          do: apply(__MODULE__, :on_timer, [state, state_payload]),
          else: :ok
      rescue
        err -> Logger.warn("[⚑⥯] on_timer raised " <> inspect(err))
      end

      @spec maybe_store(
              Finitomata.transition_resolution(),
              Finitomata.fsm_name(),
              Transition.state(),
              Transition.event(),
              Finitomata.event_payload(),
              State.payload()
            ) :: Finitomata.transition_resolution()
      case @persistency do
        nil ->
          # TODO Make it a macro
          defp maybe_store(result, _, _, _, _, _), do: result

        module when is_atom(module) ->
          defp maybe_store(
                 {:error, reason} = error,
                 name,
                 current,
                 event,
                 event_payload,
                 state_payload
               ) do
            if function_exported?(@persistency, :store_error, 2) do
              name
              |> @persistency.store_error(reason, {current, event, event_payload, state_payload})
              |> case do
                :ok ->
                  error

                {:error, persistency_error_reason} ->
                  {:error, transition: reason, persistency: persistency_error_reason}
              end
            else
              error
            end
          end

          defp maybe_store(
                 {:ok, new_state, new_state_payload} = result,
                 name,
                 current,
                 event,
                 event_payload,
                 state_payload
               ) do
            name
            |> @persistency.store(
              {new_state, new_state_payload},
              {current, event, event_payload, state_payload}
            )
            |> case do
              :ok -> result
              {:ok, updated_state_payload} -> {:ok, new_state, updated_state_payload}
              {:error, reason} -> {:error, {:persistency, reason}}
            end
          end

          defp maybe_store(result, _, _, _, _, _) do
            {:error, {:unexpected_transition_resolution, result}}
          end
      end

      @behaviour Finitomata
    end
  end

  @typedoc """
  Error types of FSM validation
  """
  @type validation_error :: :initial_state | :final_state | :orphan_from_state | :orphan_to_state

  @doc false
  @spec validate([{:transition, [binary()]}]) ::
          {:ok, [Transition.t()]} | {:error, validation_error()}
  def validate(parsed) do
    from_states = parsed |> Enum.map(fn {:transition, [from, _, _]} -> from end) |> Enum.uniq()
    to_states = parsed |> Enum.map(fn {:transition, [_, to, _]} -> to end) |> Enum.uniq()

    cond do
      Enum.count(parsed, &match?({:transition, ["[*]", _, _]}, &1)) != 1 ->
        {:error, :initial_state}

      Enum.count(parsed, &match?({:transition, [_, "[*]", _]}, &1)) < 1 ->
        {:error, :final_state}

      from_states -- to_states != [] ->
        {:error, :orphan_from_state}

      to_states -- from_states != [] ->
        {:error, :orphan_to_state}

      true ->
        {:ok, Enum.map(parsed, &(&1 |> elem(1) |> Transition.from_parsed()))}
    end
  end

  @spec fqn(fsm_name()) :: {:via, module(), {module, any()}}
  defp fqn(name), do: {:via, Registry, {Registry.Finitomata, name}}
end
