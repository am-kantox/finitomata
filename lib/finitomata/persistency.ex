defmodule Finitomata.Persistency do
  @moduledoc """
  The behaviour to be implemented by a persistent storage to be used
    with `Finitomata` (pass the implementation as `persistency: Impl.Module.Name`
    to `use Finitomata`.)

  Once declared, the initial state would attempt to load the current state from
    the storage using `load/1` funtcion which should return the `{state, payload}`
    tuple.
  """

  alias Finitomata.{State, Transition}

  @type transition_info :: %{
          from: Transition.state(),
          to: Transition.state(),
          event: Transition.event(),
          event_payload: Finitomata.event_payload(),
          object: State.payload()
        }

  @doc """
  The function to be called from `init/1` callback upon FSM start to load the state and payload
    from the persistent storage
  """
  @callback load(id :: Finitomata.fsm_name()) :: {:loaded | :created | :unknown, State.payload()}

  @doc """
  The function to be called from `on_transition/4` handler to allow storing the state
    and payload to the persistent storage
  """
  @callback store(
              id :: Finitomata.fsm_name(),
              object :: State.payload(),
              transition :: transition_info()
            ) ::
              :ok | {:ok, State.payload()} | {:error, any()}

  @doc """
  The function to be called from `on_transition/4` handler on non successful
    transition to allow storing the failed attempt to transition to the persistent storage
  """
  @callback store_error(
              id :: Finitomata.fsm_name(),
              object :: State.payload(),
              reason :: any(),
              transition :: transition_info()
            ) :: :ok | {:error, any()}

  @optional_callbacks store_error: 4
end
