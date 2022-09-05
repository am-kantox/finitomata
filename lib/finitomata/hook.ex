defmodule Finitomata.Hook do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote generated: true, location: :keep, bind_quoted: [] do
      states = @__states__
      @type state :: unquote(Enum.reduce(states, &{:|, [], [&1, &2]}))

      if :on_transition in @__impl_for__ do
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

          case Finitomata.Transition.allowed(@__fsm__, current, event) do
            [new_current] -> {:ok, new_current, state_payload}
            [] -> {:error, {:undefined_transition, {current, event}}}
            other -> {:error, {:ambiguous_transition, {current, event}, other}}
          end
        end
      end

      if :on_failure in @__impl_for__ do
        @impl Finitomata
        def on_failure(event, payload, state) do
          Logger.warn("[✗ ⇄] " <> inspect(state: state, event: event, payload: payload))
        end
      end

      if :on_enter in @__impl_for__ do
        @impl Finitomata
        def on_enter(entering, state) do
          Logger.debug("[← ⇄] " <> inspect(state: state, entering: entering))
        end
      end

      if :on_exit in @__impl_for__ do
        @impl Finitomata
        def on_exit(exiting, state) do
          Logger.debug("[→ ⇄] " <> inspect(state: state, exiting: exiting))
        end
      end

      if :on_terminate in @__impl_for__ do
        @impl Finitomata
        def on_terminate(state) do
          Logger.info("[◉ ⇄] " <> inspect(state: state))
        end
      end
    end
  end
end
