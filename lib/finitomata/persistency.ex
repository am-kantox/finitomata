defmodule Finitomata.Persistency do
  @moduledoc """
  The behaviour to be implemented by a persistent storage to be used
    with `Finitomata` (pass the implementation as `persistency: Impl.Module.Name`
    to `use Finitomata`.)

  Once declared, the FSM attempts to load its current state from the storage on start
    via `c:load/1`, and writes back on every successful transition via `c:store/3`
    (and `c:store_error/4` on a failed one).

  ## Built-in adapters

  Two zero-dependency adapters ship with the library and only require their owner
    process to be added to the supervision tree:

  - `Finitomata.Persistency.ETS` — in-memory snapshots that survive an individual
    FSM restart (good for development, tests, and single-node setups);
  - `Finitomata.Persistency.DETS` — the same, persisted to disk so snapshots survive
    a node restart.

  For database-backed persistence, implement this behaviour directly, or implement the
    `Finitomata.Persistency.Persistable` protocol for the carried struct and use the
    `Finitomata.Persistency.Protocol` adapter (see `examples/ecto_integration`).

  ## The `load/1` contract

  `Finitomata.Engine` does not call `c:load/1` with a bare id; it builds a
    `{type, fields}` descriptor from the start payload (a module, a struct, or a
    `%{type: type, id: id}` map) and expects back a `{lifecycle, {state, payload}}`
    tuple. A `:loaded` lifecycle skips the entry transition and resumes from the
    persisted `state`; `:created`/`:unknown` proceed through the normal entry flow.
  """

  alias Finitomata.{State, Transition}

  @typedoc "The entity descriptor `Finitomata.Engine` passes to `c:load/1`"
  @type load_descriptor :: {module(), keyword() | map()} | Finitomata.fsm_name()

  @typedoc "The lifecycle of the loaded entity, driving whether the entry transition runs"
  @type lifecycle :: :loaded | :created | :unknown

  @type transition_info :: %{
          from: Transition.state(),
          to: Transition.state(),
          event: Transition.event(),
          event_payload: Finitomata.event_payload(),
          object: State.payload()
        }

  @doc """
  The function to be called from `init/1` callback upon FSM start to load the state and
    payload from the persistent storage.

  It receives the `{type, fields}` descriptor built from the start payload and returns
    `{lifecycle, {state, payload}}`, where `state` is `nil` for a freshly created entity.
  """
  @callback load(descriptor :: load_descriptor()) ::
              {lifecycle(), {Transition.state() | nil, State.payload()}}

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
