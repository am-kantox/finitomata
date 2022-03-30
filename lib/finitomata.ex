defmodule Finitomata do
  @moduledoc """
  Documentation for `Finitomata`.
  """

  require Logger

  use Boundary, top_level?: true, deps: [], exports: [Supervisor, Transition]

  alias Finitomata.Transition

  defmodule State do
    @moduledoc false

    alias Finitomata.Transition

    @type payload :: any()

    @type t :: %{
            __struct__: State,
            current: Transition.state(),
            payload: payload(),
            history: [Transition.state()]
          }
    defstruct [:current, :payload, history: []]
  end

  @type event_payload :: any()

  @callback on_transition(
              Transition.state(),
              Transition.event(),
              event_payload(),
              State.payload()
            ) ::
              {:ok, Transition.state(), State.payload()} | :error
  @callback on_failure(Transition.event(), event_payload(), State.t()) :: :ok
  @callback on_terminate(State.t()) :: :ok

  @doc """
  """
  @spec start_fsm(module(), any(), any()) :: DynamicSupervisor.on_start_child()
  def start_fsm(impl, name, state),
    do: DynamicSupervisor.start_child(Finitomata.Manager, {impl, name: fqn(name), payload: state})

  @spec transition(GenServer.name(), {Transition.event(), State.payload()}) :: :ok
  def transition(target, {event, payload}),
    do: target |> fqn() |> GenServer.cast({event, payload})

  @spec state(GenServer.name()) :: State.t()
  def state(target), do: target |> fqn() |> GenServer.call(:state)

  @spec allowed?(GenServer.name(), Transition.state()) :: boolean()
  def allowed?(target, state), do: target |> fqn() |> GenServer.call({:allowed?, state})

  @spec responds?(GenServer.name(), Transition.event()) :: boolean()
  def responds?(target, event), do: target |> fqn() |> GenServer.call({:responds?, event})

  @spec alive? :: boolean()
  def alive?, do: is_pid(Process.whereis(Registry.Finitomata))

  @spec child_spec(non_neg_integer()) :: Supervisor.child_spec()
  def child_spec(id \\ 0),
    do: Supervisor.child_spec({Finitomata.Supervisor, []}, id: {Finitomata, id})

  @doc false
  defmacro __using__(plant) do
    quote location: :keep, generated: true do
      require Logger
      alias Finitomata.Transition, as: Transition
      use GenServer

      @before_compile Finitomata.Hook

      @plant (case Finitomata.PlantUML.parse(unquote(plant)) do
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

      @doc false
      def start_link(payload: payload, name: name),
        do: start_link(name: name, payload: payload)

      def start_link(name: name, payload: payload),
        do: GenServer.start_link(__MODULE__, payload, name: name)

      @doc false
      @impl GenServer
      def init(payload) do
        Process.flag(:trap_exit, true)
        {:ok, %State{current: Transition.entry(@plant), payload: payload}}
      end

      @doc false
      @impl GenServer
      def handle_call(:state, _from, state), do: {:reply, state, state}

      @doc false
      @impl GenServer
      def handle_call({:allowed?, state}, _from, state),
        do: {:reply, Transition.allowed?(@plant, state.current, state), state}

      @doc false
      @impl GenServer
      def handle_call({:responds?, event}, _from, state),
        do: {:reply, Transition.responds?(@plant, state.current, event), state}

      @doc false
      @impl GenServer
      def handle_cast({event, payload}, state) do
        with {:ok, new_current, new_payload} <-
               on_transition(state.current, event, payload, state.payload),
             true <- Transition.allowed?(@plant, state.current, new_current) do
          case new_current do
            :* ->
              {:stop, :normal, state}

            _ ->
              {:noreply,
               %State{
                 state
                 | payload: new_payload,
                   current: new_current,
                   history: [state.current | state.history]
               }}
          end
        else
          _ ->
            on_failure(event, payload, state)
            {:noreply, state}
        end
      end

      @doc false
      @impl GenServer
      def terminate(reason, state) do
        on_terminate(state)
      end

      @behaviour Finitomata
    end
  end

  @spec fqn(any()) :: {:via, module(), {module, any()}}
  defp fqn(name), do: {:via, Registry, {Registry.Finitomata, name}}
end
