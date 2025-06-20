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
            ~w|all none on_transition on_failure on_fork on_enter on_exit on_start on_terminate on_timer|a},
           {:list,
            {:in,
             ~w|on_transition on_failure on_fork on_enter on_exit on_start on_terminate on_timer|a}}
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
      doc: "When `true`, the FSM state is cached in `:persistent_term`"
    ],
    hibernate: [
      required: false,
      type: {:or, [:boolean, :atom, {:list, :atom}]},
      default: Application.compile_env(:finitomata, :hibernate, false),
      doc: "When `true`, the FSM process is hibernated between transitions"
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

  callback_types = """
  ## Types of callbacks

  Some callbacks in `Finitomata` are pure, others might mutate the inner state (payload).

  ### Pure callbacks

  - `c:Finitomata.on_enter/2` — called when the new state is entered; receives
    the state entered (the atom) and the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_exit/2` — called when the new state is exited; receives
    the state entered (the atom) and the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_failure/3` — called when the transition had failed and the target
    state has not been reached; receives the event (the atom), the event payload, and
    the whole `t:Finitomata.State.t/0`
  - `c:Finitomata.on_fork/2` — called when the `Finitomata.Fork` has been requested;
    receives the current state (the atom) and the payload `t:Finitomata.State.payload/0`
  - `c:Finitomata.on_terminate/1` — called when the finitomata is about to terminate;
    receives the whole `t:Finitomata.State.t/0`

  ### Mutating callbacks

  The following callbacks might (or might not) mutate the inner state (payload).

  - `c:Finitomata.on_start/1` — returning anything but `:ignore` amends the inner state
    to the value returned (it might be `{:continue | :ok, Finitomata.State.payload()}`)
  - `c:Finitomata.on_timer/2` — when `:ok` or `{:rescedule, non_neg_integer()}` is returned,
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

    @typedoc "The map that holds last error which happened on transition (at given state and event)."
    @type last_error ::
            %{state: Transition.state(), event: Transition.event(), error: any()} | nil

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
            hibernate: boolean() | [Transition.state()],
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
    do: id |> fqn(target) |> do_state(reload?)

  @spec do_state(
          fqn :: GenServer.name(),
          reload? :: :cached | :payload | :state | :full | (State.t() -> any())
        ) ::
          nil | State.t() | State.payload() | any()
  defp do_state(fqn, :cached), do: :persistent_term.get({Finitomata, fqn}, nil)

  defp do_state(fqn, :payload),
    do: do_state(fqn, :cached) || fqn |> do_state(:full) |> then(&(&1 && &1.payload))

  defp do_state(fqn, :state), do: do_state(fqn, :full).current

  defp do_state(fqn, full_or_fun) when full_or_fun == :full or is_function(full_or_fun, 1) do
    pid = GenServer.whereis(fqn)

    case {pid, is_pid(pid) and Process.alive?(pid), full_or_fun} do
      {nil, _, _} ->
        nil

      {_, false, _} ->
        nil

      {pid, _, :full} when is_pid(pid) ->
        pid
        |> GenServer.call(:state, 1_000)
        |> tap(&if &1.cache_state, do: :persistent_term.put({Finitomata, fqn}, &1.payload))

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

      reporter = if Code.ensure_loaded?(Mix), do: Mix.shell(), else: Logger

      telemetria_levels =
        case Keyword.fetch!(options, :telemetria_levels) do
          :none ->
            []

          some ->
            case Keyword.split(some, [:all]) do
              {[], levels} ->
                levels

              {[all: level], levels} ->
                [
                  on_transition: level,
                  on_failure: level,
                  on_fork: level,
                  on_enter: level,
                  on_exit: level,
                  on_start: level,
                  on_terminate: level,
                  on_timer: level
                ]
                |> Keyword.merge(levels)
            end
        end

      syntax = Keyword.fetch!(options, :syntax)

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

      shutdown = Keyword.fetch!(options, :shutdown)
      forks = Keyword.fetch!(options, :forks)
      auto_terminate = Keyword.fetch!(options, :auto_terminate)
      hibernate = Keyword.fetch!(options, :hibernate)
      cache_state = Keyword.fetch!(options, :cache_state)
      persistency = Keyword.fetch!(options, :persistency)
      listener = Keyword.fetch!(options, :listener)

      def_mock = fn ->
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
        |> tap(fn mox_mod ->
          Mox.defmock(mox_mod, for: Finitomata.Listener)
          Code.ensure_compiled!(mox_mod)
        end)
      end

      mox_envs = options |> Keyword.fetch!(:mox_envs) |> List.wrap()

      listener =
        case listener do
          :mox -> if Mix.env() in mox_envs, do: def_mock.()
          {:mox, listener} -> if Mix.env() in mox_envs, do: def_mock.(), else: listener
          {listener, :mox} -> if Mix.env() in mox_envs, do: def_mock.(), else: listener
          listener -> listener
        end

      use GenServer, restart: :transient, shutdown: shutdown

      impls =
        ~w|on_transition on_failure on_fork on_enter on_exit on_start on_terminate on_timer|a

      impl_for =
        case Keyword.fetch!(options, :impl_for) do
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

      dsl = options[:fsm]
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
          tos =
            fsm
            |> Enum.filter(&match?(%Transition{from: ^from, event: ^event}, &1))
            |> Enum.map(& &1.to)

          {from, %Transition{from: from, event: event, to: tos}}
        end)

      soft =
        Enum.filter(fsm, fn
          %Transition{event: event} ->
            event
            |> to_string()
            |> String.ends_with?("?")
        end)

      ensure_entry =
        options
        |> Keyword.fetch!(:ensure_entry)
        |> case do
          list when is_list(list) -> list
          true -> [Transition.entry(fsm)]
          _ -> []
        end

      timer =
        options
        |> Keyword.fetch!(:timer)
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
        forks: forks,
        persistency: persistency,
        listener: listener,
        auto_terminate: auto_terminate,
        hibernate: hibernate,
        cache_state: cache_state,
        ensure_entry: ensure_entry,
        states: Transition.states(fsm),
        events: Transition.events(fsm),
        paths: Transition.straight_paths(fsm),
        loops: Transition.loops(fsm),
        entry: Transition.entry(:transition, fsm).event,
        hard: hard,
        soft: soft,
        timer: timer
      }
      @__config_keys__ Map.keys(@__config__)
      @__config_soft_events__ Enum.map(soft, & &1.event)
      @__config_hard_states__ Keyword.keys(hard)
      @__config_fork_states__ Keyword.keys(forks)

      if @moduledoc != false do
        @moduledoc """
                   The instance of _FSM_ backed up by `Finitomata`.

                   - _entry event_ → `:#{@__config__.entry}`
                   - _forks_ → `#{if [] == @__config__.forks, do: "✗", else: inspect(@__config__.forks)}`
                   - _persistency_ → `#{if @__config__.persistency, do: inspect(@__config__.persistency), else: "✗"}`
                   - _listener_ → `#{if @__config__.listener, do: inspect(@__config__.listener), else: "✗"}`
                   - _timer_ → `#{@__config__.timer || "✗"}`
                   - _hibernate_ → `#{@__config__.hibernate || "✗"}`
                   - _cache_state_ → `#{if @__config__.cache_state, do: "✓", else: "✗"}`

                   ## FSM representation

                   ```#{@__config__.syntax |> Module.split() |> List.last() |> Macro.underscore()}
                   #{@__config__.syntax.lint(@__config__.dsl)}
                   ```

                   ### FSM paths

                   ```elixir
                   #{Enum.map_join(@__config__.paths, "\n", &inspect/1)}
                   ```

                   ### FSM loops

                   ```elixir
                   #{if [] != @__config__.loops, do: Enum.map_join(@__config__.loops, "\n", &inspect/1), else: "no loops"}
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
      def init(
            %{
              finitomata_id: id,
              name: name,
              parent: parent,
              payload: payload,
              with_persistency: persistency
            } = state
          )
          when not is_nil(name) and not is_nil(persistency) do
        {lifecycle, {state, payload}} =
          case payload do
            module when is_atom(module) ->
              persistency.load({payload, id: name})

            %struct{} = payload ->
              persistency.load({struct, payload |> Map.from_struct() |> Map.put_new(:id, name)})

            %{type: type, id: id} ->
              persistency.load({type, %{id => name}})

            other ->
              Logger.warning(
                "Loading from persisted for ‹#{inspect(state)}› failed; wrong payload: " <>
                  inspect(other)
              )

              {:failed, {nil, other}}
          end

        init(%{
          name: name,
          finitomata_id: id,
          parent: parent,
          state: state,
          payload: payload,
          lifecycle: lifecycle,
          persistency: persistency
        })
      end

      def init(%{payload: payload} = init_arg) do
        lifecycle = Map.get(init_arg, :lifecycle, :unknown)
        {state, init_arg} = Map.pop(init_arg, :state)

        init_state =
          if is_nil(state) or lifecycle in [:failed, :created] do
            init_arg
            |> safe_on_start(payload)
            |> case do
              {:stop, reason} -> {:stop, :on_start, reason}
              {:ok, payload} -> {nil, payload}
              {:continue, payload} -> {nil, payload}
              _ -> {nil, payload}
            end
          else
            {state, payload}
          end

        do_init(init_state, init_arg)
      end

      defp do_init({:stop, :on_start, reason}, init_arg),
        do: {:stop, reason: reason, init_arg: init_arg}

      defp do_init(
             {state, payload},
             %{
               finitomata_id: id,
               name: name,
               parent: parent
             } = init_arg
           ) do
        lifecycle = Map.get(init_arg, :lifecycle, :unknown)
        timer = safe_init_timer({nil, @__config__.timer})

        state =
          %State{
            name: name,
            finitomata_id: id,
            parent: parent,
            lifecycle: lifecycle,
            persistency: Map.get(init_arg, :persistency, nil),
            timer: timer,
            cache_state: @__config__.cache_state,
            hibernate: @__config__.hibernate,
            payload: payload
          }
          |> put_current_state_if_loaded(lifecycle, state)

        if @__config__.cache_state,
          do: :persistent_term.put({Finitomata, state.name}, state.payload)

        if lifecycle == :loaded,
          do: {:ok, state},
          else: {:ok, state, {:continue, {:transition, event_payload({@__config__.entry, nil})}}}
      end

      defp put_current_state_if_loaded(state, :loaded, fsm_state)
           when not is_nil(fsm_state),
           do: Map.put(state, :current, fsm_state)

      defp put_current_state_if_loaded(state, _, _fsm_state), do: state

      @doc false
      @impl GenServer
      def handle_call(:state, _from, %State{hibernate: false} = state),
        do: {:reply, state, state}

      def handle_call(:state, _from, state), do: {:reply, state, state, :hibernate}

      def handle_call({:state, fun}, _from, %State{hibernate: false} = state)
          when is_function(fun, 1),
          do: {:reply, fun.(state), state}

      def handle_call({:state, fun}, _from, %State{} = state) when is_function(fun, 1),
        do: {:reply, fun.(state), state, :hibernate}

      def handle_call(:current_state, _from, %State{hibernate: false} = state),
        do: {:reply, state.current, state}

      def handle_call(:current_state, _from, %State{} = state),
        do: {:reply, state.current, state, :hibernate}

      def handle_call(:name, _from, %State{hibernate: false} = state),
        do: {:reply, State.human_readable_name(state, false), state}

      def handle_call(:name, _from, %State{} = state),
        do: {:reply, State.human_readable_name(state, false), state, :hibernate}

      def handle_call({:allowed?, to}, _from, %State{hibernate: false} = state),
        do: {:reply, Transition.allowed?(@__config__.fsm, state.current, to), state}

      def handle_call({:allowed?, to}, _from, %State{} = state),
        do: {:reply, Transition.allowed?(@__config__.fsm, state.current, to), state, :hibernate}

      def handle_call({:responds?, event}, _from, %State{hibernate: false} = state),
        do: {:reply, Transition.responds?(@__config__.fsm, state.current, event), state}

      def handle_call({:responds?, event}, _from, state) do
        {:reply, Transition.responds?(@__config__.fsm, state.current, event), state, :hibernate}
      end

      def handle_call(whatever, _from, %State{hibernate: false} = state) do
        Logger.error(
          "Unexpected `GenServer.call/2` with a message ‹#{inspect(whatever)}›. " <>
            "`Finitomata` does not accept direct calls. Please use `on_transition/4` callback instead."
        )

        {:reply, :not_allowed, state}
      end

      def handle_call(whatever, _from, %State{} = state) do
        Logger.error(
          "Unexpected `GenServer.call/2` with a message ‹#{inspect(whatever)}›. " <>
            "`Finitomata` does not accept direct calls. Please use `on_transition/4` callback instead."
        )

        {:reply, :not_allowed, state, :hibernate}
      end

      @doc false
      @impl GenServer
      def handle_cast({event, payload}, %State{} = state),
        do: {:noreply, state, {:continue, {:transition, {event, payload}}}}

      def handle_cast({:reset_timer, tick?, new_value}, %State{} = state) do
        timer =
          if tick? do
            safe_cancel_timer(state.timer)
            Process.send(self(), :on_timer, [])
            state.timer
          else
            safe_init_timer(state.timer)
          end

        if state.hibernate,
          do: {:noreply, %{state | timer: timer}, :hibernate},
          else: {:noreply, %{state | timer: timer}}
      end

      def handle_cast(whatever, %State{} = state) do
        Logger.error(
          "Unexpected `GenServer.cast/2` with a message ‹#{inspect(whatever)}›. " <>
            "`Finitomata` does not accept direct casts. Please use `on_transition/4` callback instead."
        )

        if state.hibernate,
          do: {:noreply, state, :hibernate},
          else: {:noreply, state}
      end

      @doc false
      @impl GenServer
      def handle_continue({:transition, {event, payload}}, %State{} = state),
        do: transit({event, payload}, state)

      def handle_continue({:fork, fork_state}, %State{} = state),
        do: fork(fork_state, state)

      @doc false
      @impl GenServer
      def terminate(reason, %State{} = state) do
        safe_on_terminate(state)
      end

      @doc false
      @impl GenServer
      def handle_info(whatever, %State{} = state)
          when not is_tuple(state.timer) or not is_integer(elem(state.timer, 1)) or
                 whatever != :on_timer do
        Logger.error(
          "Unexpected message ‹#{inspect(whatever)}› received by #{inspect(State.human_readable_name(state))}. " <>
            "`Finitomata` does not accept direct messages. Please use `on_transition/4` callback instead."
        )

        if state.hibernate,
          do: {:noreply, state, :hibernate},
          else: {:noreply, state}
      end

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
      @impl GenServer
      def format_status(:normal, [pdict, state]), do: {:state, State.excerpt(state, false)}
      def format_status(:terminate, [pdict, state]), do: {:state, State.excerpt(state, true)}

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
              {:noreply, State.t()}
              | {:noreply, State.t(), :hibernate}
              | {:stop, :normal, State.t()}
      defp transit({event, payload}, %State{} = state) do
        with {:responds, true} <-
               {:responds, Transition.responds?(@__config__.fsm, state.current, event)},
             {:on_exit, :ok} <- {:on_exit, safe_on_exit(state.current, state)},
             {:ok, new_current, new_payload} <-
               safe_on_transition(state.name, state.current, event, payload, state.payload),
             new_timer <- safe_cancel_timer(state.timer),
             {:allowed, true} <-
               {:allowed, Transition.allowed?(@__config__.fsm, state.current, new_current)},
             new_history = history(state.current, state.history),
             state = %{
               state
               | payload: new_payload,
                 current: new_current,
                 history: new_history,
                 timer: safe_init_timer(new_timer)
             },
             {:on_enter, :ok} <- {:on_enter, safe_on_enter(new_current, state)} do
          if @__config__.cache_state,
            do: :persistent_term.put({Finitomata, state.name}, state.payload)

          case {new_current, state.hibernate} do
            {:*, _} ->
              {:stop, :normal, state}

            {hard, _} when hard in @__config_hard_states__ ->
              {:noreply, state,
               {:continue, {:transition, event_payload(@__config__.hard[hard].event)}}}

            {fork, _} when fork in @__config_fork_states__ ->
              {:noreply, state, {:continue, {:fork, fork}}}

            {_, false} ->
              {:noreply, state}

            {_, _} ->
              {:noreply, state, :hibernate}
          end
        else
          {err, false} ->
            Logger.warning(
              "[⚐ ↹] transition from #{state.current} with #{event} does not exists or not allowed (:#{err})"
            )

            safe_on_failure(event, payload, state)
            if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

          {err, :ok} ->
            Logger.warning("[⚐ ↹] callback failed to return `:ok` (:#{err})")
            safe_on_failure(event, payload, state)
            if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

          err ->
            state = %{state | last_error: %{state: state.current, event: event, error: err}}

            cond do
              event in @__config_soft_events__ ->
                Logger.debug("[⚐ ↹] transition softly failed " <> inspect(err))
                if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

              @__config__.fsm
              |> Transition.allowed(state.current, event)
              |> Enum.all?(&(&1 in @__config__.ensure_entry)) ->
                {:noreply, state, {:continue, {:transition, event_payload({event, payload})}}}

              true ->
                Logger.warning("[⚐ ↹] transition failed " <> inspect(err))
                safe_on_failure(event, payload, state)
                if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}
            end
        end
      end

      @spec fork(Transition.state(), State.t()) ::
              {:noreply, State.t()}
              | {:noreply, State.t(), :hibernate}
      defp fork(fork_state, %State{} = state) do
        fork_data =
          case state.payload do
            %{fork_data: %{} = fork_data} -> fork_data
            _ -> %{}
          end

        {object, fork_data} = Map.pop(fork_data, :object)
        {id, fork_data} = Map.pop(fork_data, :id)

        @__config__.forks
        |> Keyword.fetch!(fork_state)
        |> List.wrap()
        |> safe_on_fork(fork_state, state)
        |> case do
          {:ok, fork_impl, event} ->
            fsm_name = Finitomata.fsm_name(state)

            Finitomata.start_fsm(
              state.finitomata_id,
              fork_impl,
              {:fork, fork_state, fsm_name},
              %{
                owner: %{
                  event: event,
                  id: state.finitomata_id,
                  name: fsm_name,
                  pid: Finitomata.pid(state)
                },
                history: %{current: 0, steps: []},
                steps: %{passed: 0, left: Transition.steps_handled(fork_impl.__config__(:fsm))},
                object: object,
                id: id,
                data: fork_data
              }
            )

          {:error, error} ->
            Logger.warning("[⚐ ↹] fork from #{fork_state} failed (#{inspect(error)})")
        end

        if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}
      end

      @impl GenServer
      @doc false
      if @__config__.timer do
        def handle_info(:on_timer, %State{} = state) do
          state.current
          |> safe_on_timer(state)
          |> case do
            :ok ->
              if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

            {:ok, state_payload} ->
              if @__config__.cache_state,
                do: :persistent_term.put({Finitomata, state.name}, state_payload)

              state = %{state | payload: state_payload}
              if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

            {:transition, {event, event_payload}, state_payload} ->
              transit({event, event_payload}, %{state | payload: state_payload})

            {:transition, event, state_payload} ->
              transit({event, nil}, %{state | payload: state_payload})

            {:reschedule, value} ->
              timer = with {ref, _old_value} <- state.timer, do: {ref, value}
              state = %{state | timer: timer}
              if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

            weird ->
              Logger.warning("[⚑ ↹] on_timer returned a garbage " <> inspect(weird))
              if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}
          end
          |> then(fn
            {:noreply, %State{timer: timer} = state} ->
              state = %{state | timer: safe_init_timer(timer)}
              if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}

            other ->
              other
          end)
        end
      else
        def handle_info(:on_timer, %State{} = state) do
          Logger.warning(
            "[⚑ ↹] on_timer message received, but no `on_timer/2` callback is declared"
          )

          if state.hibernate, do: {:noreply, state, :hibernate}, else: {:noreply, state}
        end
      end

      @spec safe_cancel_timer(false | {reference(), pos_integer()}) ::
              false | {nil, pos_integer()}

      defp safe_cancel_timer({ref, timer}) when is_integer(timer) and timer > 0 do
        if is_reference(ref), do: Process.cancel_timer(ref, async: true, info: false)
        {nil, timer}
      end

      defp safe_cancel_timer(_false), do: false

      @spec safe_init_timer(false | {nil | reference(), pos_integer()}) ::
              false | {reference(), pos_integer()}
      defp safe_init_timer(timer) do
        case safe_cancel_timer(timer) do
          {nil, timer} when is_integer(timer) and timer > 0 ->
            {Process.send_after(self(), :on_timer, timer), timer}

          _ ->
            false
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
      @telemetria level: telemetria_levels[:on_transition],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_transition)
      defp safe_on_transition(name, current, event, event_payload, state_payload) do
        current
        |> on_transition(event, event_payload, state_payload)
        |> maybe_store(name, current, event, event_payload, state_payload)
        |> tap(&maybe_pubsub(&1, name))
      rescue
        err -> report_error(err, "on_transition/4")
      end

      @spec safe_on_fork([module()], Transition.state(), State.t()) ::
              {:ok, module(), Transition.event()} | {:error, any()}
      @telemetria level: telemetria_levels[:on_fork],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_fork)
      defp safe_on_fork(forks, fork_state, state) do
        cond do
          function_exported?(__MODULE__, :on_fork, 2) ->
            case apply(__MODULE__, :on_fork, [fork_state, state.payload]) do
              {:ok, fork_impl} ->
                case Enum.find(forks, &match?({_event, ^fork_impl}, &1)) do
                  nil -> {:error, :unknown_fork_resolution}
                  {event, ^fork_impl} -> {:ok, fork_impl, event}
                end

              :ok ->
                case forks do
                  [{event, fork_impl}] -> {:ok, fork_impl, event}
                  [] -> {:error, :missing_fork_resolution}
                  _ -> {:error, :multiple_fork_resolutions}
                end

              other ->
                {:error, :bad_fork_resolution}
            end

          match?([_fork], forks) ->
            [{event, fork_impl}] = forks
            {:ok, fork_impl, event}

          true ->
            {:error, :missing_fork_resolution}
        end
      rescue
        err ->
          report_error(err, "on_fork/2")
          {:error, :on_fork_raised}
      end

      @spec safe_on_failure(Transition.event(), Finitomata.event_payload(), State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_failure],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_failure)
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
      @telemetria level: telemetria_levels[:on_enter],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_enter)
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
      @telemetria level: telemetria_levels[:on_exit],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_exit)
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

      @spec safe_on_start(state :: :loaded | State.t(), payload :: State.payload()) ::
              {:stop, term()}
              | {:continue, State.payload()}
              | {:ok, State.payload()}
              | :ignore
      @telemetria level: telemetria_levels[:on_start],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_start)
      defp safe_on_start(state, payload)
      defp safe_on_start(:loaded, payload), do: {:ok, payload}

      defp safe_on_start(_state, payload) do
        if function_exported?(__MODULE__, :on_start, 1),
          do: apply(__MODULE__, :on_start, [payload]),
          else: :ignore
      rescue
        err ->
          report_error(err, "on_start/1")
          {:stop, err}
      end

      @spec safe_on_terminate(State.t()) :: :ok
      @telemetria level: telemetria_levels[:on_terminate],
                  group: __MODULE__,
                  if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_terminate)
      defp safe_on_terminate(state) do
        if function_exported?(__MODULE__, :on_terminate, 1) do
          with other when other != :ok <- apply(__MODULE__, :on_terminate, [state]) do
            Logger.warning(
              "[♻️] Unexpected return from `on_terminate/1` [#{inspect(other)}], must be :ok"
            )
          end
        else
          :ok
        end
      rescue
        err -> report_error(err, "on_terminate/1")
      end

      if @__config__.timer do
        @spec safe_on_timer(Transition.state(), State.t()) ::
                :ok
                | {:ok, State.t()}
                | {:transition, {Transition.state(), Finitomata.event_payload()}, State.payload()}
                | {:transition, Transition.state(), State.payload()}
                | {:reschedule, pos_integer()}
        @telemetria level: telemetria_levels[:on_timer],
                    group: __MODULE__,
                    if: Telemetria.Wrapper.telemetria?(__MODULE__, :on_timer)
        defp safe_on_timer(state, state_payload) do
          if function_exported?(__MODULE__, :on_timer, 2),
            do: apply(__MODULE__, :on_timer, [state, state_payload]),
            else: :ok
        rescue
          err -> report_error(err, "on_timer/2")
        end
      end

      @spec maybe_store(
              Finitomata.transition_resolution(),
              Finitomata.fsm_name(),
              Transition.state(),
              Transition.event(),
              Finitomata.event_payload(),
              State.payload()
            ) :: Finitomata.transition_resolution()
      case @__config__.persistency do
        nil ->
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
            with true <- function_exported?(@__config__.persistency, :store_error, 4),
                 info = %{
                   from: current,
                   to: nil,
                   event: event,
                   event_payload: event_payload,
                   object: state_payload
                 },
                 {:error, persistency_error_reason} <-
                   @__config__.persistency.store_error(name, state_payload, reason, info) do
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
            |> @__config__.persistency.store(new_state_payload, info)
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
        is_nil(@__config__.listener) ->
          :ok

        is_atom(@__config__.listener) and
            function_exported?(@__config__.listener, :after_transition, 3) ->
          defp maybe_pubsub({:ok, state, payload}, name) do
            with some when some != :ok <-
                   @__config__.listener.after_transition(name, state, payload) do
              Logger.warning(
                "[♻️] Listener ‹" <>
                  inspect(Function.capture(@__config__.listener, :after_transition, 3)) <>
                  "› returned unexpected ‹" <>
                  inspect(some) <>
                  "› when called with ‹" <> inspect([name, state, payload]) <> "›"
              )
            end
          end

        is_pid(@__config__.listener) or is_port(@__config__.listener) or
          is_atom(@__config__.listener) or is_tuple(@__config__.listener) ->
          defp maybe_pubsub({:ok, state, payload}, name) do
            send(@__config__.listener, {:finitomata, {:transition, state, payload}})
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
