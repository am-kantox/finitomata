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

  @doc """
  To be called when a `c:Finitomata.on_fork/2` resolution fails.

  Optional callback; implement it to be notified when the FSM reaches a fork state but the
    fork cannot be resolved (an unknown/ambiguous/missing fork target, a bad return, or a
    raise). `state` is the fork state and `error` is the resolution failure reason.
  """
  @doc since: "0.41.0"
  @callback after_fork_failure(
              id :: Finitomata.fsm_name(),
              state :: Transition.state(),
              error :: any()
            ) :: :ok

  @optional_callbacks after_fork_failure: 3
end
