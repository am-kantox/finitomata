defmodule Finitomata do
  @moduledoc "README.md" |> File.read!() |> String.split("\n---") |> Enum.at(1)

  require Logger
  use Boundary, top_level?: true, deps: [], exports: [Supervisor, Transition]
  alias Finitomata.Transition

  defmodule State do
    @moduledoc """
    Carries the state of the FSM.
    """

    alias Finitomata.Transition

    @typedoc "The payload that has been passed to the FSM instance on startup"
    @type payload :: any()

    @typedoc "The internal representation of the FSM state"
    @type t :: %{
            __struct__: State,
            current: Transition.state(),
            payload: payload(),
            history: [Transition.state()]
          }
    defstruct [:current, :payload, history: []]
  end

  @typedoc "The payload that can be passed to each call to `transition/3`"
  @type event_payload :: any()

  @typedoc "The name of the FSM (might be any term, but it must be unique)"
  @type fsm_name :: any()

  @doc """
  This callback will be called from each transition processor.
  """
  @callback on_transition(
              Transition.state(),
              Transition.event(),
              event_payload(),
              State.payload()
            ) ::
              {:ok, Transition.state(), State.payload()} | :error

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

  @optional_callbacks on_failure: 3, on_enter: 2, on_exit: 2, on_terminate: 1

  @doc """
  Starts the FSM instance.

  The arguments are

  - the implementation of FSM (the module, having `use Finitomata`)
  - the name of the FSM (might be any term, but it must be unique)
  - the payload to be carried in the FSM state during the lifecycle

  The FSM is started supervised.
  """
  @spec start_fsm(module(), any(), any()) :: DynamicSupervisor.on_start_child()
  def start_fsm(impl, name, payload),
    do:
      DynamicSupervisor.start_child(Finitomata.Manager, {impl, name: fqn(name), payload: payload})

  @doc """
  Initiates the transition.

  The arguments are

  - the name of the FSM
  - `{event, event_payload}` tuple; the payload will be passed to the respective
    `on_transition/4` call
  """
  @spec transition(fsm_name(), {Transition.event(), State.payload()}) :: :ok
  def transition(target, {event, payload}),
    do: target |> fqn() |> GenServer.cast({event, payload})

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
  @spec child_spec(non_neg_integer()) :: Supervisor.child_spec()
  def child_spec(id \\ 0),
    do: Supervisor.child_spec({Finitomata.Supervisor, []}, id: {Finitomata, id})

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

    if Keyword.keys(opts) -- ~w|syntax impl_for|a != [:fsm] do
      raise CompileError,
            raise_opts.("`fsm:` key is mandatory, allowed: `syntax:` and `impl_for:`")
    end

    ast(opts)
  end

  @doc false
  @doc deprecated: "Use `use fsm: …, syntax: …` instead"
  defmacro __using__({fsm, syntax}), do: ast(fsm: fsm, syntax: syntax)

  @doc false
  @doc deprecated: "Use `use fsm: …, syntax: …` instead"
  defmacro __using__(fsm), do: ast(fsm: fsm)

  @doc false
  defp ast(options \\ []) do
    quote location: :keep, generated: true do
      require Logger
      alias Finitomata.Transition, as: Transition
      use GenServer, restart: :transient, shutdown: 5_000

      @before_compile Finitomata.Hook

      @__syntax__ Keyword.get(
                    unquote(options),
                    :syntax,
                    Application.compile_env(:finitomata, :syntax, Finitomata.Mermaid)
                  )

      impls = ~w|on_transition on_failure on_enter on_exit on_terminate|a

      impl_for =
        case Keyword.get(unquote(options), :impl_for, :all) do
          :all -> impls
          :none -> []
          list when is_list(list) -> list
        end

      if impl_for -- impls != [] do
        raise CompileError,
          description:
            "allowed `impl_for:` values are: `:all`, `:none`, or any combination of `#{inspect(impls)}`"
      end

      @__impl_for__ impl_for

      @__fsm__ (case @__syntax__.parse(unquote(options[:fsm])) do
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
                end)

      @__states__ @__fsm__
                  |> Enum.flat_map(&[&1.from, &1.to])
                  |> Enum.uniq()

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

      ```#{@__syntax__ |> Module.split() |> List.last() |> Macro.underscore()}
      #{@__syntax__.lint(unquote(options[:fsm]))}
      ```
      """
      def start_link(name: name, payload: payload),
        do: GenServer.start_link(__MODULE__, payload, name: name)

      @doc false
      def start_link(payload),
        do: GenServer.start_link(__MODULE__, payload)

      @doc false
      @impl GenServer
      def init(payload),
        do: {:ok, %State{current: Transition.entry(@__fsm__), payload: payload}}

      @doc false
      @impl GenServer
      def handle_call(:state, _from, state), do: {:reply, state, state}

      @doc false
      @impl GenServer
      def handle_call({:allowed?, to}, _from, state),
        do: {:reply, Transition.allowed?(@__fsm__, state.current, to), state}

      @doc false
      @impl GenServer
      def handle_call({:responds?, event}, _from, state),
        do: {:reply, Transition.responds?(@__fsm__, state.current, event), state}

      @doc false
      @impl GenServer
      def handle_cast({event, payload}, state) do
        with {:on_exit, :ok} <- {:on_exit, safe_on_exit(state.current, state)},
             {:ok, new_current, new_payload} <-
               safe_on_transition(state.current, event, payload, state.payload),
             {:allowed, true} <-
               {:allowed, Transition.allowed?(@__fsm__, state.current, new_current)},
             state = %State{
               state
               | payload: new_payload,
                 current: new_current,
                 history: [state.current | state.history]
             },
             {:on_entry, :ok} <- {:on_entry, safe_on_enter(new_current, state)} do
          case new_current do
            :* ->
              {:stop, :normal, state}

            _ ->
              {:noreply, state}
          end
        else
          err ->
            Logger.warn("[⚐ ⇄] transition failed " <> inspect(err))
            safe_on_failure(event, payload, state)
            {:noreply, state}
        end
      end

      @doc false
      @impl GenServer
      def terminate(reason, state) do
        safe_on_terminate(state)
      end

      @spec safe_on_transition(
              Transition.state(),
              Transition.event(),
              Finitomata.event_payload(),
              State.payload()
            ) ::
              {:ok, Transition.state(), State.payload()} | :error
      defp safe_on_transition(current, event, event_payload, state_payload) do
        on_transition(current, event, event_payload, state_payload)
      rescue
        err ->
          case err do
            %{__exception__: true} ->
              {:error, Exception.message(err)}

            _ ->
              Logger.warn("[⚑ ⇄] on_transition raised " <> inspect(err))
              {:error, :on_transition_raised}
          end
      end

      @spec safe_on_failure(Transition.event(), Finitomata.event_payload(), State.t()) :: :ok
      defp safe_on_failure(event, event_payload, state_payload) do
        if function_exported?(__MODULE__, :on_failure, 3),
          do: apply(__MODULE__, :on_failure, [event, event_payload, state_payload]),
          else: :ok
      rescue
        err -> Logger.warn("[⚑ ⇄] on_failure raised " <> inspect(err))
      end

      @spec safe_on_enter(Transition.state(), State.t()) :: :ok
      defp safe_on_enter(state, state_payload) do
        if function_exported?(__MODULE__, :on_enter, 2),
          do: apply(__MODULE__, :on_enter, [state, state_payload]),
          else: :ok
      rescue
        err -> Logger.warn("[⚑ ⇄] on_enter raised " <> inspect(err))
      end

      @spec safe_on_exit(Transition.state(), State.t()) :: :ok
      defp safe_on_exit(state, state_payload) do
        if function_exported?(__MODULE__, :on_exit, 2),
          do: apply(__MODULE__, :on_exit, [state, state_payload]),
          else: :ok
      rescue
        err -> Logger.warn("[⚑ ⇄] on_exit raised " <> inspect(err))
      end

      @spec safe_on_terminate(State.t()) :: :ok
      defp safe_on_terminate(state) do
        if function_exported?(__MODULE__, :on_terminate, 1),
          do: apply(__MODULE__, :on_terminate, [state]),
          else: :ok
      rescue
        err -> Logger.warn("[⚑ ⇄] on_terminate raised " <> inspect(err))
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
