# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Finitomata do
  @doc false
  def behaviour(value, funs \\ [])

  def behaviour(value, behaviour) when is_atom(behaviour) do
    with {:module, ^behaviour} <- Code.ensure_compiled(behaviour),
         true <- function_exported?(behaviour, :behaviour_info, 1),
         funs when is_list(funs) <- behaviour.behaviour_info(:callbacks) do
      behaviour(value, funs)
    else
      _ ->
        {:error, "The behaviour specified is invalid ‹" <> inspect(value) <> "›"}
    end
  end

  def behaviour(value, funs) when is_atom(value) do
    case Code.ensure_compiled(value) do
      {:module, ^value} ->
        if Enum.all?(funs, fn {fun, arity} -> function_exported?(value, fun, arity) end) do
          {:ok, value}
        else
          {:error,
           "The module specified ‹" <>
             inspect(value) <>
             "› does not implement requested callbacks ‹" <> inspect(funs) <> "›"}
        end

      {:error, error} ->
        {:error, "Cannot find the requested module ‹" <> inspect(value) <> "› (#{error})"}
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
      type:
        {:or,
         [
           {:in, [:flowchart, :state_diagram]},
           {:custom, Finitomata, :behaviour, [Finitomata.Parser]}
         ]},
      default: :flowchart,
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
      type: {:or, [{:in, [nil]}, {:custom, Finitomata, :behaviour, [Finitomata.Persistency]}]},
      default: nil,
      doc:
        "The implementation of `Finitomata.Persistency` behaviour to backup FSM with a persistent storage."
    ],
    listener: [
      required: false,
      type:
        {:or,
         [
           {:in, [nil, :mox]},
           {:custom, Finitomata, :behaviour, [[handle_info: 2]]},
           {:custom, Finitomata, :behaviour, [Finitomata.Listener]}
         ]},
      default: nil,
      doc:
        "The implementation of `Finitomata.Listener` behaviour _or_ a `GenServer.name()` to receive notification after transitions."
    ]
  ]

  @using_schema NimbleOptions.new!(using_schema)

  use_finitomata = """

  > ### `use Finitomata` {: .info}
  >
  > When you `use Finitomata`, the Finitomata module will
  > do the following things for your module:
  >
  > - set `@behaviour Finitomata`
  > - compile and validate _FSM_ declaration, passed as `fsm:` keyword argument
  > - turn the module into `GenServer`
  > - inject default implementations of optional callbacks specified with
  >   `impl_for:` keyword argument (default: `:all`)
  > - expose a bunch of functions to query _FSM_ which would be visible in docs
  > - leaves `on_transition/4` mandatory callback to be implemeneted by
  >   the calling module and injects `before_compile` callback to validate
  >   the implementation (this option required `:finitomata` to be included
  >   in the list of compilers in `mix.exs`)

  """

  doc_options = """
  ## Options to `use Finitomata`

  #{NimbleOptions.docs(@using_schema)}
  """

  use_defstate = """
  ## State as Nested structure

  For convenience, one might use `defstate/1` macro, turning the `Finitomata`
    instance into `Estructura.Nested`, with such options as _coercion_, _validation,
    and _generation_. The example of usage would be:

  ```elixir
  use Finitomata, ...

  defstate %{value: :integer, retries: %{attempts: :integer, errors: [:string]}}
  ```    
  """

  doc_readme = "README.md" |> File.read!() |> String.split("\n---") |> Enum.at(1)

  @moduledoc Enum.join([doc_readme, use_finitomata, doc_options], "\n\n")

  require Logger

  alias Finitomata.Transition

  @typedoc """
  The ID of the `Finitomata` supervision tree, useful for the concurrent
    using of different `Finitomata` supervision trees.
  """
  @type id :: any()

  @typedoc "The name of the FSM (might be any term, but it must be unique)"
  @type fsm_name :: any()

  @typedoc "The payload that can be passed to each call to `transition/3`"
  @type event_payload :: any()

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
            lifecycle: :loaded | :created | :unknown,
            persistency: nil | module(),
            listener: nil | module(),
            current: Transition.state(),
            payload: payload(),
            timer: non_neg_integer(),
            history: [Transition.state()],
            last_error: last_error()
          }
    defstruct name: nil,
              lifecycle: :unknown,
              persistency: nil,
              listener: nil,
              current: :*,
              payload: %{},
              timer: false,
              history: [],
              last_error: nil

    @doc false
    def human_readable_name(%State{name: name}, registry? \\ true) do
      default_registry = Finitomata.Supervisor.registry_name(nil)

      case {registry?, name} do
        {_, {:via, Registry, {^default_registry, name}}} -> name
        {false, {:via, Registry, {_, name}}} -> name
        {true, {:via, Registry, {registry, name}}} -> {registry, name}
        other -> other
      end
    end

    @doc false
    def persisted?(%State{lifecycle: :unknown}), do: false
    def persisted?(%State{lifecycle: :loaded}), do: true
    def persisted?(%State{lifecycle: :created}), do: true

    @doc false
    def errored?(%State{last_error: nil}), do: false

    def errored?(%State{last_error: %{error: {:error, kind}} = error}),
      do: [{kind, Map.delete(error, :error)}]

    def errored?(%State{last_error: %{error: error}}), do: error
    def errored?(%State{last_error: error}), do: error

    @doc false
    def previous_state(%State{history: []}), do: nil
    def previous_state(%State{history: [{last, _} | _]}), do: last
    def previous_state(%State{history: [last | _]}), do: last

    @doc "Exposes the short excerpt from state of FSM which is log-friendly"
    def excerpt(%State{} = state, payload? \\ true) do
      %{
        finitomata: State.human_readable_name(state),
        state: state.current
      }
      |> Map.merge(if payload?, do: %{payload: state.payload}, else: %{})
      |> Map.merge(if errored?(state), do: %{error: errored?(state)}, else: %{})
      |> Map.merge(if previous_state(state), do: %{previous: previous_state(state)}, else: %{})
      |> Map.to_list()
    end

    @history_size Application.compile_env(:finitomata, :history_size, 5)

    @doc false
    def history_size, do: @history_size

    defimpl Inspect do
      @moduledoc false
      import Inspect.Algebra

      alias Finitomata.State

      def inspect(%State{} = state, %Inspect.Opts{} = opts) do
        doc =
          if true == get_in(opts.custom_options, [:full]) do
            state |> Map.from_struct() |> Map.to_list()
          else
            name = State.human_readable_name(state)
            persisted? = State.persisted?(state)
            errored? = State.errored?(state)
            previous = State.previous_state(state)

            [
              name: name,
              state: [
                current: state.current,
                previous: previous,
                payload: state.payload
              ],
              internals: [
                errored?: errored?,
                persisted?: persisted?,
                timer: state.timer
              ]
            ]
          end

        concat(["#Finitomata<", to_doc(doc, opts), ">"])
      end
    end
  end

  @doc """
  This callback will be called from each transition processor.
  """
  @callback on_transition(
              current_state :: Transition.state(),
              event :: Transition.event(),
              event_payload :: event_payload(),
              state_payload :: State.payload()
            ) :: transition_resolution()

  @doc """
  This callback will be called from the underlying `c:GenServer.init/1`.

  Unlike other callbacks, this one might raise preventing the whole FSM from start.

  When `:ignore`, or `{:continues, new_payload}` tuple is returned from the callback,
     the normal initalization continues through continuing to the next state.

  `{:ok, new_payload}` prevents the _FSM_ from automatically getting into start state,
    and the respective transition must be called manually.
  """
  @callback on_start(state :: State.payload()) ::
              {:continue, State.payload()} | {:ok, State.payload()} | :ignore

  @doc """
  This callback will be called if the transition failed to complete to allow
  the consumer to take an action upon failure.
  """
  @callback on_failure(
              event :: Transition.event(),
              event_payload :: event_payload(),
              state :: State.t()
            ) :: :ok

  @doc """
  This callback will be called on entering the state.
  """
  @callback on_enter(current_state :: Transition.state(), state :: State.t()) :: :ok

  @doc """
  This callback will be called on exiting the state.
  """
  @callback on_exit(current_state :: Transition.state(), state :: State.t()) :: :ok

  @doc """
  This callback will be called on transition to the final state to allow
  the consumer to perform some cleanup, or like.
  """
  @callback on_terminate(state :: State.t()) :: :ok

  @doc """
  This callback will be called recurrently if `timer: pos_integer()`
    option has been given to `use Finitomata`.
  """
  @callback on_timer(current_state :: Transition.state(), state :: State.t()) ::
              :ok
              | {:ok, State.payload()}
              | {:transition, {Transition.event(), event_payload()}, State.payload()}
              | {:transition, Transition.event(), State.payload()}
              | {:reschedule, non_neg_integer()}

  @optional_callbacks on_start: 1,
                      on_failure: 3,
                      on_enter: 2,
                      on_exit: 2,
                      on_terminate: 1,
                      on_timer: 2

  @doc """
  Starts the FSM instance.

  The arguments are

  - the global name of `Finitomata` instance (optional, defaults to `Finitomata`)
  - the name of the FSM (might be any term, but it must be unique)
  - the implementation of FSM (the module, having `use Finitomata`)
  - the payload to be carried in the FSM state during the lifecycle

  Before `v0.15.0` the second and third parameters were expected in different order.
  This is deprecated and will be removed in `v1.0.0`.

  The FSM is started supervised. If the global name/id is given, it should be passed
    to all calls like `transition/4`
  """
  @spec start_fsm(id(), any() | module(), module() | any(), any()) ::
          DynamicSupervisor.on_start_child()
  def start_fsm(id \\ nil, name, impl, payload)

  def start_fsm(id, impl, name, payload) when is_atom(impl) and not is_atom(name),
    do: do_start_fsm(id, name, impl, payload)

  def start_fsm(id, name, impl, payload) when is_atom(impl) and not is_atom(name),
    do: do_start_fsm(id, name, impl, payload)

  def start_fsm(id, ni1, ni2, payload) when is_atom(ni1) and is_atom(ni2) do
    case {Code.ensure_loaded?(ni1), Code.ensure_loaded?(ni2)} do
      {true, false} -> do_start_fsm(id, ni2, ni1, payload)
      {_, true} -> do_start_fsm(id, ni1, ni2, payload)
    end
  end

  defp do_start_fsm(id, name, impl, payload) when is_atom(impl) do
    DynamicSupervisor.start_child(
      Finitomata.Supervisor.manager_name(id),
      {impl, name: fqn(id, name), payload: payload}
    )
  end

  @doc """
  Initiates the transition.

  The arguments are

  - the id of the FSM (optional)
  - the name of the FSM
  - `event` atom or `{event, event_payload}` tuple; the payload will be passed to the respective
    `on_transition/4` call, payload is `nil` by default
  - `delay` (optional) the interval in milliseconds to apply transition after
  """
  @spec transition(
          id(),
          fsm_name(),
          Transition.event() | {Transition.event(), State.payload()},
          non_neg_integer()
        ) ::
          :ok
  def transition(id \\ nil, target, event_payload, delay \\ 0)

  def transition(target, {event, payload}, delay, 0) when is_integer(delay),
    do: transition(nil, target, {event, payload}, delay)

  def transition(id, target, event, delay) when is_atom(event) and is_integer(delay),
    do: transition(id, target, {event, nil}, delay)

  def transition(id, target, {event, payload}, 0),
    do: id |> fqn(target) |> GenServer.cast({event, payload})

  def transition(id, target, {event, payload}, delay) when is_integer(delay) and delay > 0 do
    fn ->
      Process.sleep(delay)
      id |> fqn(target) |> GenServer.cast({event, payload})
    end
    |> Task.start()
    |> elem(0)
  end

  @doc """
  Fast check to validate the FSM process with such `id` and `target` exists.

  The arguments are

  - the id of the FSM (optional)
  - the name of the FSM
  """
  @spec lookup(id(), fsm_name()) :: pid() | nil
  def lookup(id \\ nil, target) do
    with {:via, registry_impl, {registry, ^target}} <- fqn(id, target),
         [{pid, _state}] when is_pid(pid) <- registry_impl.lookup(registry, target),
         do: pid,
         else: (_ -> nil)
  end

  @doc """
  The state of the FSM.

  The arguments are

  - the id of the FSM (optional)
  - the name of the FSM
  - defines whether the cached state might be returned or should be reloaded
  """
  @spec state(id(), fsm_name(), reload? :: :cached | :payload | :full) ::
          nil | State.t() | State.payload()
  def state(id \\ nil, target, reload? \\ :full)

  def state(target, reload?, :full) when reload? in ~w|cached payload full|a,
    do: state(nil, target, reload?)

  def state(id, target, reload?),
    do: id |> fqn(target) |> do_state(reload?)

  @spec do_state(fqn :: GenServer.name(), reload? :: :cached | :payload | :full) ::
          nil | State.t() | State.payload()
  defp do_state(fqn, :cached), do: :persistent_term.get({Finitomata, fqn}, nil)
  defp do_state(fqn, :payload), do: do_state(fqn, :cached) || do_state(fqn, :full).payload

  defp do_state(fqn, :full) do
    fqn
    |> GenServer.whereis()
    |> case do
      nil ->
        nil

      pid when is_pid(pid) ->
        {:ok, state} = :gen.call(pid, :"$gen_call", :state, 1_000)
        :persistent_term.put({Finitomata, fqn}, state.payload)
        state
    end
  catch
    :exit, :normal -> nil
  end

  @doc """
  Returns `true` if the transition to the state `state` is possible, `false` otherwise.
  """
  @spec allowed?(id(), fsm_name(), Transition.state()) :: boolean()
  def allowed?(id \\ nil, target, state),
    do: id |> fqn(target) |> GenServer.call({:allowed?, state})

  @doc """
  Returns `true` if the transition by the event `event` is possible, `false` otherwise.
  """
  @spec responds?(id(), fsm_name(), Transition.event()) :: boolean()
  def responds?(id \\ nil, target, event),
    do: id |> fqn(target) |> GenServer.call({:responds?, event})

  @doc """
  Returns supervision tree of `Finitomata`. The healthy tree has all three `pid`s.
  """
  @spec sup_tree(id()) :: [
          {:supervisor, nil | pid()},
          {:manager, nil | pid()},
          {:registry, nil | pid()}
        ]
  def sup_tree(id \\ nil) do
    [
      supervisor: Process.whereis(Finitomata.Supervisor.supervisor_name(id)),
      manager: Process.whereis(Finitomata.Supervisor.manager_name(id)),
      registry: Process.whereis(Finitomata.Supervisor.registry_name(id))
    ]
  end

  @doc """
  Returns `true` if the supervision tree is alive, `false` otherwise.
  """
  @spec sup_alive?(id()) :: boolean()
  def sup_alive?(id \\ nil),
    do: id |> sup_tree() |> Keyword.values() |> Enum.all?(&(not is_nil(&1)))

  @doc """
  Returns `true` if the _FSM_ specified is alive, `false` otherwise.
  """
  @spec alive?(any(), fsm_name()) :: boolean()
  def alive?(id \\ nil, target), do: id |> fqn(target) |> GenServer.whereis() |> is_pid()

  @doc """
  Helper to match finitomata state from history, which can be `:state`, or `{:state, reenters}`
  """
  @spec match_state?(
          matched :: Finitomata.Transition.state(),
          state :: Finitomata.Transition.state() | {Finitomata.Transition.state(), pos_integer()}
        ) :: boolean()
  def match_state?(state, state), do: true
  def match_state?(state, {state, _reenters}), do: true
  def match_state?({state, _reenters}, state), do: true
  def match_state?({state, _}, {state, _}), do: true
  def match_state?(_, _), do: false

  @doc false
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(id \\ nil)

  def child_spec(nil),
    do: Supervisor.child_spec(Finitomata.Supervisor, [])

  def child_spec(id),
    do: Supervisor.child_spec({Finitomata.Supervisor, id}, id: {Finitomata, id})

  @doc false
  @spec start_link(any()) ::
          {:ok, pid} | {:error, {:already_started, pid()} | {:shutdown, term()} | term()}
  def start_link(id \\ nil) do
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
      NimbleOptions.validate!(unquote(options), unquote(Macro.escape(schema)))

      require Logger

      alias Finitomata.Transition, as: Transition
      import Finitomata.Defstate, only: [defstate: 1]

      @on_definition Finitomata.Hook
      @before_compile Finitomata.Hook

      reporter = if Code.ensure_loaded?(Mix), do: Mix.shell(), else: Logger

      syntax =
        Keyword.get(
          unquote(options),
          :syntax,
          Application.compile_env(:finitomata, :syntax, :flowchart)
        )

      if syntax in [Finitomata.Mermaid, Finitomata.PlantUML] do
        reporter.info([
          [:yellow, "deprecated: ", :reset],
          "using built-in modules as syntax names is deprecated, please use ",
          [:blue, ":flowchart", :reset],
          " and/or ",
          [:blue, ":state_diagram", :reset],
          " instead"
        ])
      end

      syntax =
        case syntax do
          :flowchart -> Finitomata.Mermaid
          :state_diagram -> Finitomata.PlantUML
          module when is_atom(module) -> module
        end

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

      persistency =
        Keyword.get(
          unquote(options),
          :persistency,
          Application.compile_env(:finitomata, :persistency, nil)
        )

      listener =
        Keyword.get(
          unquote(options),
          :listener,
          Application.compile_env(:finitomata, :listener, nil)
        )

      listener =
        with :mox <- listener do
          if Mix.env() == :test do
            with {:error, error} <- Code.ensure_compiled(Mox) do
              reporter.info([
                [:yellow, "expectation: ", :reset],
                "to be able to use ",
                [:blue, ":mox", :reset],
                " listener in tests with ",
                [:blue, "`Finitomata.ExUnit`", :reset],
                ", please add ",
                [:blue, "`{:mox, \"~> 1.0\", only: [:test]}`", :reset],
                " as a dependency to your ",
                [:blue, "`mix.exs`", :reset],
                " project file (got: ",
                [:yellow, inspect(error), :reset],
                ")"
              ])
            end

            [__MODULE__, Mox]
            |> Module.concat()
            |> tap(&Mox.defmock(&1, for: Finitomata.Listener))
          end
        end

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

      dsl = unquote(options[:fsm])

      env = __ENV__

      fsm =
        case syntax.parse(dsl, env) do
          {:ok, result} ->
            result

          {:error, description, snippet, _context, {file, line, column}, _offset} ->
            raise SyntaxError,
              file: file,
              line: line,
              column: column,
              description: description,
              snippet: snippet

          {:error, error} ->
            raise TokenMissingError,
              file: env.file,
              line: env.line,
              column: 0,
              opening_delimiter: ~s|"""|,
              description: "description is incomplete, error: #{inspect(error)}",
              snippet: dsl |> String.split("\n", parts: 2) |> hd()
        end

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

      [Transition.hard(fsm), hard]
      |> Enum.map(fn h -> h |> Enum.map(&elem(&1, 1)) |> Enum.uniq() end)
      |> Enum.reduce(&Kernel.--/2)
      |> unless do
        raise CompileError,
          description:
            "transitions marked as `:hard` must be determined, non-determined found: #{inspect(Transition.hard(fsm) -- hard)}"
      end

      hard =
        Enum.map(hard, fn {from, event} ->
          {from, Enum.find(fsm, &match?(%Transition{from: ^from, event: ^event}, &1))}
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
        dsl: dsl,
        impl_for: impl_for,
        persistency: persistency,
        listener: listener,
        auto_terminate: auto_terminate,
        ensure_entry: ensure_entry,
        states: Transition.states(fsm),
        events: Transition.events(fsm),
        paths: Transition.paths(fsm),
        loops: Transition.loops(fsm),
        entry: Transition.entry(:transition, fsm).event,
        hard: hard,
        soft: soft,
        timer: timer
      }
      @__config_keys__ Map.keys(@__config__)
      @__config_soft_events__ Enum.map(soft, & &1.event)
      @__config_hard_states__ Keyword.keys(hard)

      if @moduledoc != false do
        @moduledoc """
                   The instance of _FSM_ backed up by `Finitomata`.

                   ## FSM representation

                   ```#{@__config__[:syntax] |> Module.split() |> List.last() |> Macro.underscore()}
                   #{@__config__[:syntax].lint(@__config__[:dsl])}
                   ```
                   """ <> if(is_nil(@moduledoc), do: "", else: "\n---\n" <> @moduledoc)
      end

      @doc """
      The convenient macro to allow using states in guards, returns a compile-time
        list of states for `#{inspect(__MODULE__)}`.
      """
      defmacro config(key) when key in @__config_keys__ do
        value = @__config__ |> Map.get(key) |> Macro.escape()
        quote do: unquote(value)
      end

      @doc """
      Getter for the internal compiled-in _FSM_ information.
      """
      @spec __config__(atom()) :: any()
      def __config__(key) when key in @__config_keys__,
        do: Map.get(@__config__, key)

      @doc false
      @doc deprecated: "Use `__config__(:fsm)` instead"
      def fsm, do: Map.get(@__config__, :fsm)

      @doc false
      @doc deprecated: "Use `__config__(:entry)` instead"
      def entry, do: Transition.entry(fsm())

      @doc false
      @doc deprecated: "Use `__config__(:states)` instead"
      def states, do: Map.get(@__config__, :states)

      @doc false
      @doc deprecated: "Use `__config__(:events)` instead"
      def events, do: Map.get(@__config__, :events)

      @doc ~s"""
      Starts an _FSM_ alone with `name` and `payload` given.

      Usually one does not want to call this directly, the most common way would be
      to start a `Finitomata` supervision tree or even better embed it into
      the existing supervision tree _and_ start _FSM_ with `Finitomata.start_fsm/4`
      passing `#{inspect(__MODULE__)}` as the first parameter.

      For distributed applications, use `Infinitomata.start_fsm/4` instead.
      """
      def start_link(payload: payload, name: name),
        do: start_link(name: name, payload: payload)

      case @__config__[:persistency] do
        nil ->
          def start_link(name: name, payload: payload) do
            GenServer.start_link(__MODULE__, %{name: name, payload: payload}, name: name)
          end

          def start_link(payload),
            do: GenServer.start_link(__MODULE__, %{name: nil, payload: payload})

        module when is_atom(module) ->
          def start_link(name: name, payload: payload) do
            GenServer.start_link(
              __MODULE__,
              %{name: name, payload: payload, with_persistency: @__config__[:persistency]},
              name: name
            )
          end
      end

      defmacrop report_error(err, from \\ "Finitomata") do
        quote generated: true, location: :keep, bind_quoted: [err: err, from: from] do
          case err do
            %{__exception__: true} ->
              {ex, st} = Exception.blame(:error, err, __STACKTRACE__)
              Logger.warning(Exception.format(:error, ex, st))
              {:error, Exception.message(err)}

            _ ->
              Logger.warning(
                "[⚑ ↹] #{from} raised: " <> inspect(err) <> "\n" <> inspect(__STACKTRACE__)
              )

              {:error, :on_transition_raised}
          end
        end
      end

      @doc false
      @impl GenServer
      def init(%{name: name, payload: payload, with_persistency: persistency} = state)
          when not is_nil(name) and not is_nil(persistency) do
        {lifecycle, payload} =
          case payload do
            module when is_atom(module) ->
              persistency.load({payload, id: name})

            %struct{} = payload ->
              persistency.load({struct, payload |> Map.from_struct() |> Map.put_new(:id, name)})

            %{type: type, id: id} ->
              persistency.load({type, %{id => name}})
          end

        init(%{name: name, payload: payload, lifecycle: lifecycle, persistency: persistency})
      end

      def init(%{name: name, payload: payload} = init_arg) do
        lifecycle = Map.get(init_arg, :lifecycle, :unknown)

        {lifecycle, payload} =
          case function_exported?(__MODULE__, :on_start, 1) and
                 apply(__MODULE__, :on_start, [payload]) do
            false -> {lifecycle, payload}
            {:ok, payload} -> {:loaded, payload}
            {:continue, payload} -> {lifecycle, payload}
            :ignore -> {lifecycle, payload}
          end

        state =
          %State{
            name: name,
            lifecycle: lifecycle,
            persistency: Map.get(init_arg, :persistency, nil),
            timer: @__config__[:timer],
            payload: payload
          }
          |> put_current_state_if_loaded(lifecycle, payload)

        :persistent_term.put({Finitomata, state.name}, state.payload)

        if is_integer(@__config__[:timer]) and @__config__[:timer] > 0,
          do: Process.send_after(self(), :on_timer, @__config__[:timer])

        if lifecycle == :loaded,
          do: {:ok, state},
          else:
            {:ok, state, {:continue, {:transition, event_payload({@__config__[:entry], nil})}}}
      end

      defp put_current_state_if_loaded(state, :loaded, payload),
        do: Map.put(state, :current, payload.state)

      defp put_current_state_if_loaded(state, _, payload), do: state

      @doc false
      @impl GenServer
      def handle_call(:state, _from, state), do: {:reply, state, state}

      @doc false
      @impl GenServer
      def handle_call(:name, _from, state),
        do: {:reply, State.human_readable_name(state, false), state}

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
      def handle_call(whatever, _from, state) do
        Logger.error(
          "Unexpected `GenServer.call/2` with a message ‹#{inspect(whatever)}›. " <>
            "`Finitomata` does not accept direct calls. Please use `on_transition/4` callback instead."
        )

        {:reply, :not_allowed, state}
      end

      @doc false
      @impl GenServer
      def handle_cast({event, payload}, state),
        do: {:noreply, state, {:continue, {:transition, {event, payload}}}}

      @doc false
      @impl GenServer
      def handle_cast(whatever, state) do
        Logger.error(
          "Unexpected `GenServer.cast/2` with a message ‹#{inspect(whatever)}›. " <>
            "`Finitomata` does not accept direct casts. Please use `on_transition/4` callback instead."
        )

        {:noreply, state}
      end

      @doc false
      @impl GenServer
      def handle_continue({:transition, {event, payload}}, state),
        do: transit({event, payload}, state)

      @doc false
      @impl GenServer
      def terminate(reason, state) do
        safe_on_terminate(state)
      end

      @doc false
      @impl GenServer

      def handle_info(whatever, state)
          when not is_integer(state.timer) or whatever != :on_timer do
        Logger.error(
          "Unexpected message ‹#{inspect(whatever)}› received by #{State.human_readable_name(state)}. " <>
            "`Finitomata` does not accept direct messages. Please use `on_transition/4` callback instead."
        )

        {:noreply, state}
      end

      @doc false
      @impl GenServer
      def code_change(_old_vsn, state, extra) when extra in [[], %{}, nil],
        do: {:ok, state}

      @doc false
      @impl GenServer
      def code_change(_old_vsn, state, _extra) do
        Logger.warning(
          "Hot code swapping is requested. `Finitomata` does not accept changes through hot swap. " <>
            "The request would be ignored."
        )

        {:ok, state}
      end

      @doc false
      @impl GenServer
      def format_status(:normal, [pdict, state]) do
        {:state, State.excerpt(state, false)}
      end

      @doc false
      @impl GenServer
      def format_status(:terminate, [pdict, state]) do
        {:state, State.excerpt(state, true)}
      end

      @spec history(Transition.state(), [Transition.state()]) :: [Transition.state()]
      defp history(current, history) do
        history
        |> case do
          [^current | rest] -> [{current, 2} | rest]
          [{^current, count} | rest] -> [{current, count + 1} | rest]
          _ -> [current | history]
        end
        |> Enum.take(State.history_size())
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
          :persistent_term.put({Finitomata, state.name}, state.payload)

          case new_current do
            :* ->
              {:stop, :normal, state}

            hard when hard in @__config_hard_states__ ->
              {:noreply, state,
               {:continue, {:transition, event_payload(@__config__[:hard][hard].event)}}}

            _ ->
              {:noreply, state}
          end
        else
          {err, false} ->
            Logger.warning(
              "[⚐ ↹] transition from #{state.current} with #{event} does not exists or not allowed (:#{err})"
            )

            safe_on_failure(event, payload, state)
            {:noreply, state}

          {err, :ok} ->
            Logger.warning("[⚐ ↹] callback failed to return `:ok` (:#{err})")
            safe_on_failure(event, payload, state)
            {:noreply, state}

          err ->
            state = %State{state | last_error: %{state: state.current, event: event, error: err}}

            cond do
              event in @__config_soft_events__ ->
                Logger.debug("[⚐ ↹] transition softly failed " <> inspect(err))
                {:noreply, state}

              @__config__[:fsm]
              |> Transition.allowed(state.current, event)
              |> Enum.all?(&(&1 in @__config__[:ensure_entry])) ->
                {:noreply, state, {:continue, {:transition, event_payload({event, payload})}}}

              true ->
                Logger.warning("[⚐ ↹] transition failed " <> inspect(err))
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

            {:ok, state_payload} ->
              :persistent_term.put({Finitomata, state.name}, state_payload)
              {:noreply, %State{state | payload: state_payload}}

            {:transition, {event, event_payload}, state_payload} ->
              transit({event, event_payload}, %State{state | payload: state_payload})

            {:transition, event, state_payload} ->
              transit({event, nil}, %State{state | payload: state_payload})

            {:reschedule, value} when is_integer(value) and value >= 0 ->
              {:noreply, %State{state | timer: value}}

            weird ->
              Logger.warning("[⚑ ↹] on_timer returned a garbage " <> inspect(weird))
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
        |> tap(&maybe_pubsub(&1, name))
      rescue
        err -> report_error(err, "on_transition/4")
      end

      @spec safe_on_failure(Transition.event(), Finitomata.event_payload(), State.t()) :: :ok
      defp safe_on_failure(event, event_payload, state_payload) do
        if function_exported?(__MODULE__, :on_failure, 3) do
          with other when other != :ok <-
                 apply(__MODULE__, :on_failure, [event, event_payload, state_payload]) do
            Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> report_error(err, "on_failure/3")
      end

      @spec safe_on_enter(Transition.state(), State.t()) :: :ok
      defp safe_on_enter(state, state_payload) do
        if function_exported?(__MODULE__, :on_enter, 2) do
          with other when other != :ok <- apply(__MODULE__, :on_enter, [state, state_payload]) do
            Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> report_error(err, "on_enter/2")
      end

      @spec safe_on_exit(Transition.state(), State.t()) :: :ok
      defp safe_on_exit(state, state_payload) do
        if function_exported?(__MODULE__, :on_exit, 2) do
          with other when other != :ok <- apply(__MODULE__, :on_exit, [state, state_payload]) do
            Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> report_error(err, "on_exit/2")
      end

      @spec safe_on_terminate(State.t()) :: :ok
      defp safe_on_terminate(state) do
        if function_exported?(__MODULE__, :on_terminate, 1) do
          with other when other != :ok <- apply(__MODULE__, :on_terminate, [state]) do
            Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
            :ok
          end
        else
          :ok
        end
      rescue
        err -> report_error(err, "on_terminate/1")
      end

      @spec safe_on_timer(Transition.state(), State.t()) ::
              :ok
              | {:ok, State.t()}
              | {:transition, {Transition.state(), Finitomata.event_payload()}, State.payload()}
              | {:transition, Transition.state(), State.payload()}
              | {:reschedule, pos_integer()}
      defp safe_on_timer(state, state_payload) do
        if function_exported?(__MODULE__, :on_timer, 2),
          do: apply(__MODULE__, :on_timer, [state, state_payload]),
          else: :ok
      rescue
        err -> report_error(err, "on_timer/2")
      end

      @spec maybe_store(
              Finitomata.transition_resolution(),
              Finitomata.fsm_name(),
              Transition.state(),
              Transition.event(),
              Finitomata.event_payload(),
              State.payload()
            ) :: Finitomata.transition_resolution()
      case @__config__[:persistency] do
        nil ->
          # TODO Make it a macro
          defp maybe_store(result, _, _, _, _, _), do: result

        module when is_atom(module) ->
          defp maybe_store(
                 {:error, reason},
                 name,
                 current,
                 event,
                 event_payload,
                 state_payload
               ) do
            with true <- function_exported?(@__config__[:persistency], :store_error, 4),
                 info = %{
                   from: current,
                   to: nil,
                   event: event,
                   event_payload: event_payload,
                   object: state_payload
                 },
                 {:error, persistency_error_reason} <-
                   @__config__[:persistency].store_error(name, state_payload, reason, info) do
              {:error, transition: reason, persistency: persistency_error_reason}
            else
              _ ->
                {:error, transition: reason}
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
            info = %{
              from: current,
              to: new_state,
              event: event,
              event_payload: event_payload,
              object: state_payload
            }

            name
            |> @__config__[:persistency].store(new_state_payload, info)
            |> case do
              :ok -> result
              {:ok, updated_state_payload} -> {:ok, new_state, updated_state_payload}
              {:error, reason} -> {:error, persistency: reason}
            end
          end

          defp maybe_store(result, _, _, _, _, _) do
            {:error, transition: result}
          end
      end

      @spec maybe_pubsub(Finitomata.transition_resolution(), Finitomata.fsm_name()) :: :ok
      cond do
        is_nil(@__config__[:listener]) ->
          :ok

        is_atom(@__config__[:listener]) and
            function_exported?(@__config__[:listener], :after_transition, 3) ->
          defp maybe_pubsub({:ok, state, payload}, name) do
            with some when some != :ok <-
                   @__config__[:listener].after_transition(name, state, payload) do
              Logger.warning(
                "[♻️] Listener ‹" <>
                  inspect(Function.capture(@__config__[:listener], :after_transition, 3)) <>
                  "› returned unexpected ‹" <>
                  inspect(some) <>
                  "› when called with ‹" <> inspect([name, state, payload]) <> "›"
              )
            end
          end

        is_pid(@__config__[:listener]) or is_port(@__config__[:listener]) or
          is_atom(@__config__[:listener]) or is_tuple(@__config__[:listener]) ->
          defp maybe_pubsub({:ok, state, payload}, name) do
            send(@__config__[:listener], {:finitomata, {:transition, state, payload}})
          end
      end

      defp maybe_pubsub(_, _), do: :ok

      @behaviour Finitomata
    end
  end

  @typedoc """
  Error types of FSM validation
  """
  @type validation_error :: :initial_state | :final_state | :orphan_from_state | :orphan_to_state

  @doc false
  @spec validate([{:transition, [binary()]}], Macro.Env.t()) ::
          {:ok, [Transition.t()]} | {:error, validation_error()}
  def validate(parsed, _env \\ __ENV__) do
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

  @spec fqn(any(), fsm_name()) :: {:via, module(), {module, any()}}
  @doc "Fully qualified name of the _FSM_ backed by `Finitonata`"
  def fqn(id, name),
    do: {:via, Registry, {Finitomata.Supervisor.registry_name(id), name}}
end
