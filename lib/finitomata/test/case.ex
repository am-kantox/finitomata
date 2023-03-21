defmodule ExUnitFinitomata do
  @moduledoc """
  Helpers and assertions to make `Finitomata` implementation easily testable.
  """

  use Boundary

  @states Finitomata.Test.Listener.states

  defmacro assert_transition(id \\ nil, target, event_payload, to_state, block) do
    IO.inspect({id, target, event_payload, to_state, block})
    quote do
      Finitomata.transition(unquote(id), unquote(target), unquote(event_payload))
      to_state = Finitomata.state(unquote(id), unquote(target), :full)
      case unquote(to_state) do
        nil -> assert is_nil(to_state)
        state when state in unquote(@states) ->
          assert %Finitomata.State{current: unquote(to_state)} = to_state
      end

    end
  end
end
