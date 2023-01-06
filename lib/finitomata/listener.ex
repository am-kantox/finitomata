defmodule Finitomata.Listener do
  @moduledoc """
  The behaviour to be implemented and passed to `use Finitomata` to receive
    all the state transitions notifications.
  """

  alias Finitomata.{State, Transition}

  @doc "To be called after a successful transition"
  @callback after_transition(
              id :: Finitomata.fsm_name(),
              state :: Transition.state(),
              payload :: State.payload()
            ) :: :ok
end
