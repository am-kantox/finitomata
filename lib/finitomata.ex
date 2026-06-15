defmodule Finitomata do
  @doc false
  def behaviour(value, funs \\ [])

  def behaviour(value, behaviour) when is_atom(behaviour) do
    with {:module, ^behaviour} <- Code.ensure_compiled(behaviour),
         true <- function_exported?(behaviour, :behaviour_info, 1),
         funs when is_list(funs) <- behaviour.behaviour_info(:callbacks) do
      # only the mandatory callbacks must be implemented; optional ones may be omitted
      behaviour(value, funs -- behaviour_optional_callbacks(behaviour))
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

  @spec behaviour_optional_callbacks(module()) :: [{atom(), arity()}]
  defp behaviour_optional_callbacks(behaviour) do
    behaviour.behaviour_info(:optional_callbacks)
  rescue
    _ -> []
  end

  using_schema = [
    fsm: [
      required: true,
      type: :string,
      doc: "The FSM declaration with the syntax defined by `syntax` option."
    ],
    forks: [
      required: false,
      # [AM] Allow runtime fork amending (:string)
      # type: {:list, {:tuple, [:atom, {:or, [:atom, :string, {:list, {:or, [:atom, :string]}}]}]}},
      type:
        {:list,
         {:tuple, [:atom, {:or, [{:tuple, [:atom, :atom]}, {:list, {:tuple, [:atom, :atom]}}]}]}},
      default: [],
      doc:
        "The keyword list of states and modules where the FSM forks and awaits for another process to finish"
    ],
    syntax: [
      required: false,
      type:
        {:or,
         [
           {:in, [:flowchart, :state_diagram]},
           {:custom, Finitomata, :behaviour, [Finitomata.Parser]}
         ]},
      default: Application.compile_env(:finitomata, :syntax, :flowchart),
      doc: "The FSM dialect parser to convert the declaration to internal FSM representation."
    ],
    impl_for: [
      required: false,
      type:
        {:or,
         [
           {:in,
            ~w|all none on_transition on_failure on_rollback on_fork on_enter on_exit on_start on_terminate on_timer|a},
           {:list,
            {:in,
             ~w|on_transition on_failure on_rollback on_fork on_enter on_exit on_start on_terminate on_timer|a}}
         ]},
      default: Application.compile_env(:finitomata, :impl_for, :all),
      doc: "The list of transitions to inject default implementation for."
    ],
    telemetria_levels: [
      required: false,
      type:
        {:or,
         [
           {:in, [:none]},
           # ~w|all on_transition on_failure on_fork on_enter on_exit on_start on_terminate on_timer|a}
           :keyword_list
         ]},
      default:
        Application.compile_env(:finitomata, :telemetria_levels,
          all: :info,
          on_enter: :debug,
          on_exit: :debug,
          on_failure: :warning,
          on_timer: :debug
        ),
      doc: "The telemetría level for selected callbacks"
    ],
    timer: [
      required: false,
      type: {:or, [:boolean, :pos_integer]},
      default: Application.compile_env(:finitomata, :timer, false),
      doc: "The interval to call `on_timer/2` recurrent event."
    ],
    auto_terminate: [
      required: false,
      type: {:or, [:boolean, :atom, {:list, :atom}]},
      default: Application.compile_env(:finitomata, :auto_terminate, false),
      doc: "When `true`, the transition to the end state is initiated automatically."
    ],
    cache_state: [
      required: false,
      type: :boolean,
      default: Application.compile_env(:finitomata, :cache_state, true),
      doc:
        "When `true`, the FSM payload is cached for fast `state/3` reads (see `Finitomata.StateCache`; the backend defaults to `:ets` and is configurable via `config :finitomata, :cache_backend`)"
    ],
    hibernate: [
      required: false,
      type: {:or, [:boolean, :atom, {:list, :atom}]},
      default: Application.compile_env(:finitomata, :hibernate, false),
      doc:
        "When `true`, the FSM process is hibernated between transitions; pass a `state()` or `[state()]` to hibernate only when the FSM rests in (one of) the given state(s)"
    ],
    ensure_entry: [
      required: false,
      type: {:or, [{:list, :atom}, :boolean]},
      default: Application.compile_env(:finitomata, :ensure_entry, []),
      doc: "The list of states to retry transition to until succeeded."
    ],
    shutdown: [
      required: false,
      type: :pos_integer,
      default: Application.compile_env(:finitomata, :shutdown, 5_000),
      doc: "The shutdown interval for the `GenServer` behind the FSM."
    ],
    persistency: [
      required: false,
      type: {:or, [{:in, [nil]}, {:custom, Finitomata, :behaviour, [Finitomata.Persistency]}]},
      default: Application.compile_env(:finitomata, :persistency, nil),
      doc:
        "The implementation of `Finitomata.Persistency` behaviour to backup FSM with a persistent storage."
    ],
    listener: [
      required: false,
      type:
        {:or,
         [
           {:in, [nil, :mox]},
           {:tuple,
            [
              {:in, [:mox]},
              {:custom, Finitomata, :behaviour, [Finitomata.Listener]}
            ]},
           {:custom, Finitomata, :behaviour, [[handle_info: 2]]},
           {:custom, Finitomata, :behaviour, [Finitomata.Listener]}
         ]},
      default: Application.compile_env(:finitomata, :listener, nil),
      doc:
        "The implementation of `Finitomata.Listener` behaviour _or_ a `GenServer.name()` to receive notification after transitions."
    ],
    mox_envs: [
      required: false,
      type: {:or, [:atom, {:list, :atom}]},
      default: Application.compile_env(:finitomata, :mox_envs, :test),
      doc: "The list of environments to implement `mox` listener for"
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
  > - leaves `on_transition/4` mandatory callback to be implemented by
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

  callback_types = """
  ## Types of callbacks

  Some callbacks in `Finitomata` are pure, others might mutate the inner state (payload).

  ### Pure callbacks

  - `c:Finitomata.on_enter/2` — called when the new state is entered; receives
    the state entered (the atom) and the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_exit/2` — called when the new state is exited; receives
    the state entered (the atom) and the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_failure/3` — called when the transition had failed and the target
    state has not been reached; receives the event (the atom), the event payload, and
    the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_rollback/3` — called when `on_transition/4` resolved to a state that
    is not allowed from the current one, to let the consumer compensate the side effects
    of the rejected transition; receives the event (the atom), the event payload, and
    the whole `t:Finitomata.State.t/0` (with `last_error` set)
  - `c:Finitomata.on_fork/2` — called when the `Finitomata.Fork` has been requested;
    receives the current state (the atom) and the payload `t:Finitomata.State.payload/0`
  - `c:Finitomata.on_terminate/1` — called when the finitomata is about to terminate;
    receives the whole `t:Finitomata.State.t/0`

  ### Mutating callbacks

  The following callbacks might (or might not) mutate the inner state (payload).

  - `c:Finitomata.on_start/1` — returning anything but `:ignore` amends the inner state
    to the value returned (it might be `{:continue | :ok, Finitomata.State.payload()}`)
  - `c:Finitomata.on_timer/2` — when `:ok` or `{:reschedule, non_neg_integer()}` is returned,
    this callback is pure, it’s potentially mutating otherwise
  - `c:Finitomata.on_transition/4` — as the main driving callback of the _FSM_, it’s
    definitively mutating, unless errored
  """

  use_with_telemetria = """
  ## Use with `Telemetría`

  `telemetria` library can be used to send all the state changes to the backend,
    configured by this library. To enable metrics sending, one should do the following.

  ### Add `telemetria` dependency

  `telemetria` dependency should be added alongside its backend dependency.
     For `:telemetry` backend, that would be

  ```elixir
  defp deps do
    [
      ...
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetria, "~> 0.22"}
    ]
  ```

  ### Configure `telemetria` library in a compile-time config

  ```elixir
  config :telemetria,
    backend: Telemetria.Backend.Telemetry,
    purge_level: :debug,
    level: :info,
  ```

  ### Add `:telemetria` compiler
  `:telemetria` compiler should be added to the list of `mix` compilers, alongside
    `:finitomata` compiler.

  ```elixir
  def project do
    [
      ...
      compilers: [:finitomata, :telemetria | Mix.compilers()],
      ...
    ]
  end
  ```

  ### Configure `:finitomata` to use `:telemetria`

  The configuration parameter `[:finitomata, :telemetria]` accepts the following values:

  - `false` — `:telemetria` metrics won’t be sent
  - `true` — `:telemetria` metrics will be send for _all_ the callbacks
  - `[callback, ...]` — `:telemetria` metrics will be send for the specified callbacks

  Available callbacks may be seen below in this module documentation. Please note,
    that the events names would be `event: [__MODULE__, :safe_on_transition]` and like.

  ```elixir
  config :finitomata, :telemetria, true
  ```

  See [`telemetria`](https://hexdocs.pm/telemetria) docs for further config details.
  """

  doc_readme = "README.md" |> File.read!() |> String.split("\n---") |> Enum.at(1)

  @moduledoc Enum.join(
               [doc_readme, use_finitomata, callback_types, use_with_telemetria, doc_options],
               "\n\n"
             )

  require Logger

  alias Finitomata.Transition

  @typedoc """
  The ID of the `Finitomata` supervision tree, useful for the concurrent
    using of different `Finitomata` supervision trees.
  """
  @type id :: any()

  @typedoc "The name of the FSM (might be any term, but it must be unique)"
  @type fsm_name :: any()

  @typedoc "The implementation of the FSM (basically, the module having `use Finitomata` clause)"
  @type implementation :: module()

  @typedoc "The implementation of the Flow (basically, the module having `use Finitomata.Flow` clause)"
  @type flow_implementation :: module()

  @typedoc "The payload that is carried by `Finitomata` instance, returned by `Finitomata.state/2`"
  @type payload :: term()

  @typedoc "The payload that can be passed to each call to `transition/3`"
  @type event_payload :: term()

  @typedoc "The resolution of transition, when `{:error, _}` tuple, the transition is aborted"
  @type transition_resolution ::
          {:ok, Transition.state(), Finitomata.State.payload()} | {:error, any()}

  @typedoc "The resolution of fork"
  @type fork_resolution :: {:ok, flow_implementation()} | :ok

  defmodule State do
    @moduledoc """
    Carries the state of the FSM.
    """

    alias Finitomata.Transition

    @typedoc "The payload that has been passed to the FSM instance on startup"
    @type payload :: any()

    @typedoc "The parent process for this particular FSM implementation"
    @type parent :: nil | pid()

    @typedoc "The last error which happened on transition; see `Finitomata.Error`."
    @type last_error :: Finitomata.Error.t() | nil

    @typedoc "The internal representation of the FSM state"
    @type t :: %{
            __struct__: State,
            name: Finitomata.fsm_name(),
            finitomata_id: Finitomata.id(),
            parent: parent(),
            lifecycle: :loaded | :created | :failed | :unknown,
            persistency: nil | module(),
            listener: nil | module(),
            current: Transition.state(),
            payload: payload(),
            timer: false | {reference(), pos_integer()},
            cache_state: boolean(),
            hibernate: boolean() | Transition.state() | [Transition.state()],
            history: [Transition.state()],
            last_error: last_error()
          }
    defstruct name: nil,
              finitomata_id: nil,
              parent: nil,
              lifecycle: :unknown,
              persistency: nil,
              listener: nil,
              current: :*,
              payload: %{},
              timer: false,
              cache_state: true,
              hibernate: false,
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
    def persisted?(%State{lifecycle: :loaded}), do: true
    def persisted?(%State{lifecycle: :created}), do: true
    def persisted?(_), do: false

    @doc false
    def errored?(%State{last_error: nil}), do: false

    def errored?(%State{
          last_error: %Finitomata.Error{reason: reason, state: state, event: event}
        })
        when is_atom(reason) and not is_nil(reason),
        do: [{reason, %{state: state, event: event}}]

    def errored?(%State{last_error: %Finitomata.Error{reason: reason}}), do: reason

    # legacy shapes for states persisted before `Finitomata.Error` existed
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
            self = Finitomata.pid(state)

            [
              name: name,
              pids: [self: self, parent: state.parent],
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

  > #### Auto-driven transitions reshape the payload {: .info}
  >
  > For transitions initiated by `Finitomata` itself — the initial entry transition,
  > _hard_ (banged, e.g. `start!`) transitions, and `ensure_entry` retries — the
  > `event_payload` is normalized into a map carrying a `__retries__` counter
  > (a non-map payload `p` becomes `%{payload: p, __retries__: n}`). Handlers matching
  > on those events should account for this shape. Payloads passed to a manual
  > `transition/4` call are delivered to `on_transition/4` unchanged.
  """
  @callback on_transition(
              current_state :: Transition.state(),
              event :: Transition.event(),
              event_payload :: event_payload(),
              state_payload :: State.payload()
            ) :: transition_resolution()

  @doc """
  This callback will be called when the transition processor encounters fork state.
  """
  @callback on_fork(
              current_state :: Transition.state(),
              state_payload :: State.payload()
            ) :: fork_resolution()

  @doc """
  This callback will be called from the underlying `c:GenServer.init/1`.

  Unlike other callbacks, this one might raise preventing the whole FSM from start.

  When `:ok`, `:ignore`, or `{:continue, new_payload}` tuple is returned from the callback,
     the normal initalization continues through continuing to the next state.

  `{:ok, new_payload}` prevents the _FSM_ from automatically getting into start state,
    and the respective transition must be called manually.
  """
  @callback on_start(state :: State.payload()) ::
              {:continue, State.payload()} | {:ok, State.payload()} | :ignore | :ok

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
  This callback will be called when `on_transition/4` succeeded yet resolved to a target
  state that is not allowed from the current one, so the transition is rejected and the
  FSM stays put.

  It lets the consumer compensate (roll back) any side effects performed inside
  `on_transition/4` for the now-rejected transition. The `state` carries the original
  (pre-transition) payload and a `t:Finitomata.Error.t/0` in `:last_error` whose `:reason`
  is `{:not_allowed, from, rejected_to}`. `c:Finitomata.on_failure/3` is still invoked
  afterwards.

  Because the `:allowed?` guard runs before the persistency and the listener are touched,
  a rejected transition is **not** persisted and does **not** notify the listener.
  """
  @doc since: "0.41.0"
  @callback on_rollback(
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

  By design, `Finitomata` library is the in-memory solution (unless `persistency: true`
  is set in options _and_ the persistency layer is implemented by the consumer’s code.)

  That being said, the consumer should not rely on `on_timer/2` consistency between restarts.
  """
  @callback on_timer(current_state :: Transition.state(), state :: State.t()) ::
              :ok
              | {:ok, State.payload()}
              | {:transition, {Transition.event(), event_payload()}, State.payload()}
              | {:transition, Transition.event(), State.payload()}
              | {:reschedule, non_neg_integer()}

  @optional_callbacks on_start: 1,
                      on_failure: 3,
                      on_rollback: 3,
                      on_enter: 2,
                      on_exit: 2,
                      on_terminate: 1,
                      on_timer: 2,
                      on_fork: 2

  @behaviour Finitomata.Supervisor

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
  @impl Finitomata.Supervisor
  def start_fsm(id \\ nil, name, impl, payload)

  def start_fsm(id, impl, name, payload) when is_atom(impl) and not is_atom(name),
    do: do_start_fsm(id, name, impl, payload)

  def start_fsm(id, name, impl, payload) when is_atom(impl) and not is_atom(name),
    do: do_start_fsm(id, name, impl, payload)

  def start_fsm(id, ni1, ni2, payload) when is_atom(ni1) and is_atom(ni2) do
    if Application.get_env(:finitomata, :warn_ambiguous_start_fsm, true) do
      Logger.warning(
        "[⚐ ↹] `start_fsm/4` got two atoms (" <>
          inspect(ni1) <>
          ", " <>
          inspect(ni2) <>
          "); the name/implementation order is being guessed by probing which one is a " <>
          "loadable module. This legacy disambiguation is deprecated and will be removed in " <>
          "v1.0.0 — pass a non-atom FSM name (e.g. a string) to avoid the ambiguity, or set " <>
          "`config :finitomata, warn_ambiguous_start_fsm: false` to silence this warning."
      )
    end

    case {Code.ensure_loaded?(ni1), Code.ensure_loaded?(ni2)} do
      {true, false} -> do_start_fsm(id, ni2, ni1, payload)
      {_, true} -> do_start_fsm(id, ni1, ni2, payload)
    end
  end

  defp do_start_fsm(id, name, impl, payload) when is_atom(impl) do
    {parent, payload} =
      case payload do
        %{} ->
          Map.pop(payload, :parent, self())

        _ ->
          if Keyword.keyword?(payload),
            do: Keyword.pop(payload, :parent, self()),
            else: {self(), payload}
      end

    DynamicSupervisor.start_child(
      Finitomata.Supervisor.manager_name(id),
      {impl, id: id, name: fqn(id, name), parent: parent, payload: payload}
    )
  end

  @impl Finitomata.Supervisor
  def timer_tick(id \\ nil, target),
    do: id |> fqn(target) |> GenServer.whereis() |> send(:on_timer)

  @doc """
  Returns a plain version of the FSM name as it has been passed to `start_fsm/4`
  """
  @spec fsm_name(State.t()) :: Finitomata.fsm_name()
  def fsm_name(%State{name: {:via, _registry, {_registry_name, name}}}), do: name
  def fsm_name(_), do: nil

  @doc """
  Returns an `id` of the finitomata instance the FSM runs on
  """
  @spec finitomata_id(State.t()) :: Finitomata.id()
  def finitomata_id(%State{finitomata_id: id}), do: id

  @doc """
  Looks up and returns the PID of the FSM by the `State.t()`.
  """
  # [AM] maybe reverse lookup the self name here?
  # https://www.erlang.org/doc/apps/erts/erlang.html#t:registered_process_identifier/0
  @spec pid(State.t()) :: pid() | nil
  def pid(%State{name: fsm_name}) do
    with {:via, registry, {registry_name, name}} <- fsm_name,
         [{pid, _}] <- registry.lookup(registry_name, name),
         do: pid,
         else: (_ -> nil)
  rescue
    e in [ArgumentError] ->
      Logger.warning("Error looking up the PID: #{e.message}")
      nil
  end

  @doc """
  Looks up and returns the PID of the FSM by the `State.t()`.
  """
  @spec pid(Finitomata.id(), Finitomata.fsm_name()) :: pid() | nil
  def pid(id \\ nil, name) do
    with {:via, registry, {registry_name, name}} <- fqn(id, name),
         [{pid, _}] <- registry.lookup(registry_name, name),
         do: pid,
         else: (_ -> nil)
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
  @impl Finitomata.Supervisor
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
  @impl Finitomata.Supervisor
  def state(id \\ nil, target, reload? \\ :full)

  def state(target, reload?, :full)
      when is_function(reload?, 1) or reload? in ~w|cached payload state full|a,
      do: state(nil, target, reload?)

  def state(id, target, reload?),
    do: do_state(id, fqn(id, target), reload?)

  @spec do_state(
          id :: Finitomata.id(),
          fqn :: GenServer.name(),
          reload? :: :cached | :payload | :state | :full | (State.t() -> any())
        ) ::
          nil | State.t() | State.payload() | any()
  defp do_state(id, fqn, :cached), do: Finitomata.StateCache.get(id, fqn)

  defp do_state(id, fqn, :payload),
    do: do_state(id, fqn, :cached) || id |> do_state(fqn, :full) |> then(&(&1 && &1.payload))

  defp do_state(id, fqn, :state), do: do_state(id, fqn, :full).current

  defp do_state(id, fqn, full_or_fun)
       when full_or_fun == :full or is_function(full_or_fun, 1) do
    pid = GenServer.whereis(fqn)

    case {pid, is_pid(pid) and Process.alive?(pid), full_or_fun} do
      {nil, _, _} ->
        nil

      {_, false, _} ->
        nil

      {pid, _, :full} when is_pid(pid) ->
        pid
        |> GenServer.call(:state, 1_000)
        |> tap(&if &1.cache_state, do: Finitomata.StateCache.put(id, fqn, &1.payload))

      {pid, _, fun} when is_pid(pid) and is_function(fun, 1) ->
        GenServer.call(pid, {:state, fun}, 1_000)
    end
  catch
    :exit, {:normal, {GenServer, :call, _}} -> nil
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
  @impl Finitomata.Supervisor
  def alive?(id \\ nil, target), do: id |> fqn(target) |> GenServer.whereis() |> is_pid()

  @doc """
  Helper to match finitomata state from history, which can be `:state`, or `{:state, reenters}`
  """
  @spec match_state?(
          matched :: Finitomata.Transition.state(),
          state :: Finitomata.Transition.state() | {Finitomata.Transition.state(), pos_integer()}
        ) :: boolean()
  def match_state?(matched, state)
  def match_state?(state, state), do: true
  def match_state?(state, {state, _reenters}), do: true
  def match_state?({state, _reenters}, state), do: true
  def match_state?({state, _}, {state, _}), do: true
  def match_state?(_, _), do: false

  @doc false
  @impl Finitomata.Supervisor
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
      options = NimbleOptions.validate!(unquote(options), unquote(Macro.escape(schema)))

      require Logger

      use Telemetria.Wrapper

      alias Finitomata.Transition, as: Transition
      import Finitomata.Defstate, only: [defstate: 1]

      @on_definition Finitomata.Hook
      @before_compile Finitomata.Hook

      shutdown = Keyword.fetch!(options, :shutdown)

      # `timer`'s `Application.compile_env/3` default must be captured in this (the consuming
      #   module's) compile-time context, so it is resolved here and passed to the builder.
      timer =
        case Keyword.fetch!(options, :timer) do
          value when is_integer(value) and value >= 0 -> value
          true -> Application.compile_env(:finitomata, :timer, 5_000)
          _ -> false
        end

      {config, telemetria_levels} = Finitomata.ConfigBuilder.build(options, __ENV__, timer)

      @__config__ config
      @__config_keys__ Map.keys(@__config__)

      use GenServer, restart: :transient, shutdown: shutdown

      if @moduledoc != false do
        @moduledoc Finitomata.ConfigBuilder.moduledoc(@__config__, @moduledoc)
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
        do: start_link(id: nil, name: name, parent: self(), payload: payload)

      case @__config__.persistency do
        nil ->
          def start_link(id: id, name: name, parent: parent, payload: payload) do
            GenServer.start_link(
              __MODULE__,
              %{name: name, finitomata_id: id, parent: parent, payload: payload},
              name: name
            )
          end

          def start_link(payload),
            do:
              GenServer.start_link(__MODULE__, %{
                name: nil,
                finitomata_id: nil,
                parent: self(),
                payload: payload
              })

        module when is_atom(module) ->
          def start_link(id: id, name: name, parent: parent, payload: payload) do
            GenServer.start_link(
              __MODULE__,
              %{
                name: name,
                finitomata_id: id,
                parent: parent,
                payload: payload,
                with_persistency: @__config__.persistency
              },
              name: name
            )
          end
      end

      @doc false
      @impl GenServer
      def init(init_arg), do: Finitomata.Engine.init(__MODULE__, init_arg)

      @doc false
      @spec safe_on_start(:loaded | map(), State.payload()) ::
              {:stop, term()} | {:continue, State.payload()} | {:ok, State.payload()} | :ignore
      def safe_on_start(state, payload),
        do: Finitomata.Engine.safe_on_start(__MODULE__, state, payload)

      @doc false
      @impl GenServer
      def handle_call(msg, _from, %State{} = state),
        do: Finitomata.Engine.handle_call(__MODULE__, msg, state)

      @doc false
      @impl GenServer
      def handle_cast(msg, %State{} = state),
        do: Finitomata.Engine.handle_cast(__MODULE__, msg, state)

      @doc false
      @impl GenServer
      def handle_continue(continuation, %State{} = state),
        do: Finitomata.Engine.handle_continue(__MODULE__, continuation, state)

      @doc false
      @impl GenServer
      def terminate(reason, %State{} = state),
        do: Finitomata.Engine.terminate(__MODULE__, reason, state)

      @doc false
      @impl GenServer
      def handle_info(msg, %State{} = state),
        do: Finitomata.Engine.handle_info(__MODULE__, msg, state)

      @doc false
      @impl GenServer
      def code_change(_old_vsn, %State{} = state, extra) when extra in [[], %{}, nil],
        do: {:ok, state}

      @doc false
      @impl GenServer
      def code_change(_old_vsn, %State{} = state, _extra) do
        Logger.warning(
          "Hot code swapping is requested. `Finitomata` does not accept changes through hot swap. " <>
            "The request would be ignored."
        )

        {:ok, state}
      end

      @doc false
      if Version.compare(System.version(), "1.15.9") == :gt do
        @impl GenServer
      end

      def format_status(%{state: %State{} = fsm_state} = status),
        do: %{status | state: State.excerpt(fsm_state, Map.has_key?(status, :reason))}

      def format_status(status), do: status

      @doc false
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
      @telemetria level: telemetria_levels[:on_transition],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_transition)
      def safe_on_transition(name, current, event, event_payload, state_payload),
        do:
          Finitomata.Engine.safe_on_transition(
            __MODULE__,
            name,
            current,
            event,
            event_payload,
            state_payload
          )

      @doc false
      @spec safe_on_fork([module()], Transition.state(), State.t()) ::
              {:ok, module(), Transition.event()} | {:error, any()}
      @telemetria level: telemetria_levels[:on_fork],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_fork)
      def safe_on_fork(forks, fork_state, state),
        do: Finitomata.Engine.safe_on_fork(__MODULE__, forks, fork_state, state)

      @doc false
      @spec safe_on_failure(Transition.event(), Finitomata.event_payload(), State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_failure],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_failure)
      def safe_on_failure(event, event_payload, state_payload),
        do: Finitomata.Engine.safe_on_failure(__MODULE__, event, event_payload, state_payload)

      @doc false
      @spec safe_on_enter(Transition.state(), State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_enter],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_enter)
      def safe_on_enter(state, state_payload),
        do: Finitomata.Engine.safe_on_enter(__MODULE__, state, state_payload)

      @doc false
      @spec safe_on_exit(Transition.state(), State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_exit],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_exit)
      def safe_on_exit(state, state_payload),
        do: Finitomata.Engine.safe_on_exit(__MODULE__, state, state_payload)

      @doc false
      @spec safe_on_terminate(State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_terminate],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_terminate)
      def safe_on_terminate(state),
        do: Finitomata.Engine.safe_on_terminate(__MODULE__, state)

      if @__config__.timer do
        @doc false
        @spec safe_on_timer(Transition.state(), State.t()) ::
                :ok
                | {:ok, State.t()}
                | {:transition, {Transition.state(), Finitomata.event_payload()}, State.payload()}
                | {:transition, Transition.state(), State.payload()}
                | {:reschedule, pos_integer()}
        @telemetria level: telemetria_levels[:on_timer],
                    group: __MODULE__,
                    if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_timer)
        def safe_on_timer(state, state_payload),
          do: Finitomata.Engine.safe_on_timer(__MODULE__, state, state_payload)
      end

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

      not Enum.any?(parsed, &match?({:transition, [_, "[*]", _]}, &1)) ->
        {:error, :final_state}

      from_states -- to_states != [] ->
        {:error, :orphan_from_state}

      to_states -- from_states != [] ->
        {:error, :orphan_to_state}

      true ->
        {:ok, Enum.map(parsed, &(&1 |> elem(1) |> Transition.from_parsed()))}
    end
  end

  @spec fqn(id(), fsm_name()) :: {:via, module(), {module, any()}}
  @doc "Fully qualified name of the _FSM_ backed by `Finitonata`"
  def fqn(id, name),
    do: {:via, Registry, {Finitomata.Supervisor.registry_name(id), name}}

  @doc since: "0.23.3"
  @impl Finitomata.Supervisor
  def all(id \\ nil) do
    pid_to_module =
      id
      |> Finitomata.Supervisor.manager_name()
      |> DynamicSupervisor.which_children()
      |> Enum.flat_map(fn
        {_undefined, pid, :worker, [module]} -> [{pid, module}]
        _ -> []
      end)
      |> Map.new()

    id
    |> Finitomata.Supervisor.registry_name()
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Map.new(fn {name, pid} ->
      {name, %{pid: pid, module: Map.get(pid_to_module, pid, :unknown)}}
    end)
  end
end
