defmodule Finitomata.Hook do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote do
      @impl Finitomata
      def on_transition(current, event, event_payload, state_payload) do
        Logger.debug(
          "[✓ ⇄] with: " <>
            inspect(
              current: current,
              event: event,
              event_payload: event_payload,
              state: state_payload
            )
        )

        case Finitomata.PlantUML.allowed(@plant, current, event) do
          [new_current] -> {:ok, new_current, state_payload}
          _other -> :error
        end
      end

      @impl Finitomata
      def on_failure(event, payload, state) do
        Logger.warn(
          "[✗ ⇄] " <> inspect(state: state, event: event, payload: payload) <> " has failed"
        )
      end
    end
  end
end
