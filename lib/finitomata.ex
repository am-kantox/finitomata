defmodule Finitomata do
  @moduledoc """
  Documentation for `Finitomata`.
  """

  require Logger

  defmodule State do
    @moduledoc false
    @type name :: atom()
    @type payload :: any()

    @type t :: %{
            current: name(),
            payload: payload(),
            history: [name()]
          }
    defstruct [:current, :payload, history: []]
  end

  @type event_name :: atom()
  @type event_payload :: any()
  @type event :: {event_name(), State.payload()}

  @callback on_transition(State.name(), event_name(), event_payload(), State.payload()) ::
              {:ok, State.name(), State.payload()} | :error
  @callback on_failure(event_name(), event_payload(), State.t()) :: :ok

  @doc """
  """
  @spec transition(GenServer.name(), event()) :: :ok
  def transition(target, {event, payload}) do
    GenServer.cast(target, {event, payload})
  end

  defmacro __using__(plant) do
    quote location: :keep, generated: true do
      alias Finitomata.PlantUML, as: P
      require Logger
      use GenServer

      @before_compile Finitomata.Hook

      @plant (case P.parse(unquote(plant)) do
                {:ok, result} -> result
                error -> raise SyntaxError, error
              end)

      def start_link(name, payload),
        do: GenServer.start_link(__MODULE__, payload, name: name)

      def init(payload),
        do: {:ok, %State{current: P.entry(@plant), payload: payload}}

      def handle_cast({event, payload}, state) do
        with {:ok, new_current, new_payload} <-
               on_transition(state.current, event, payload, state.payload),
             true <- P.allowed?(@plant, state.current, new_current) do
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

      @behaviour Finitomata
    end
  end
end
