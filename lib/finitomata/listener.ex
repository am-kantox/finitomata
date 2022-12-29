defmodule Finitomata.Listener do
  @moduledoc """
  The behaviour to be implemented and passed to `use Finitomata` to receive
    all the state transitions notifications.
  """

  alias Finitomata.{State, Transition}

  @doc "To be called upon a transition"
  @callback after_transition(Finitomata.fsm_name(), Transition.state(), State.payload()) :: :ok
end
