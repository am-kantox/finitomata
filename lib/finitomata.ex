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
  @spec transition(GenServer.name(), {Transition.event(), State.payload()}) :: :ok
  def transition(target, {event, payload}),
    do: target |> fqn() |> GenServer.cast({event, payload})

  @spec state(GenServer.name()) :: State.t()
  def state(target), do: target |> fqn() |> GenServer.call(:state)

  @spec fqn(any()) :: {:via, module(), {module, any()}}
  def fqn(name), do: {:via, Registry, {Registry.Finitomata, name}}

  defmacro __using__(plant) do
    quote location: :keep, generated: true do
      require Logger
      alias Finitomata.Transition, as: Transition
      use GenServer

      @before_compile Finitomata.Hook

      @plant (case Finitomata.PlantUML.parse(unquote(plant)) do
                {:ok, result} -> result
                error -> raise SyntaxError, error
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
end
