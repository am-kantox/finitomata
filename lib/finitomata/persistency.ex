defmodule Finitomata.Persistency do
  @moduledoc """
  The behaviour to be implemented by a persistent storage to be used
    with `Finitomata` (pass the implementation as `persistency: Impl.Module.Name`
    to `use Finitomate`.)

  Once declared, the initial state would attempt to load the current state from
    the storage using `load/1` funtcion which should return the `{state, payload}`
    tuple.
  """

  alias Finitomata.{State, Transition}

  @doc """
  The function to be called from `init/1` callback upon FSM start to load the state and payload
    from the persistent storage
  """
  @callback load(
              name :: Finitomata.fsm_name(),
              payload :: State.payload()
            ) ::
              State.payload()

  @doc """
  The function to be called from `on_transition/4` handler to allow storing the state
    and payload to the persistent storage
  """
  @callback store(
              name :: Finitomata.fsm_name(),
              state :: Transition.state(),
              payload :: State.payload()
            ) ::
              :ok | {:error, any()}
  @doc """
  The function to be called from `on_transition/4` handler on non successful
    transition to allow storing the failed attempt to transition to the persistent storage
  """
  @callback store_error(
              name :: Finitomata.fsm_name(),
              reason :: any(),
              payload :: State.payload()
            ) ::
              :ok | {:error, any()}

  @optional_callbacks store_error: 3
end
