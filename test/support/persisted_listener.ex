defmodule Finitomata.Test.PersistedPayload do
  @moduledoc false
  # Carried by `Finitomata.Test.PersistedListener`. `resume_at` decides which lifecycle the
  #   fixture exercises: a state means storage has something to resume from, `nil` means the
  #   entity is new and the entry transition should run.
  defstruct resume_at: nil, value: 0
end

defmodule Finitomata.Test.ResumingPersistency do
  @moduledoc false
  # Minimal `Finitomata.Persistency` for the `ex_unit` fixtures. Loading deliberately hands
  #   back a payload that differs from the one the test passed, which is the case a pinned
  #   payload assertion in `init_finitomata/6` could never match.

  @behaviour Finitomata.Persistency

  alias Finitomata.Test.PersistedPayload

  @impl Finitomata.Persistency
  def load({PersistedPayload, fields}) do
    payload = struct(PersistedPayload, fields)
    # Storage hands back its own copy whichever lifecycle this is; bumping `value` stands in
    #   for that, and is what a test cannot know to pin in advance.
    loaded = %{payload | value: payload.value + 1}

    case payload.resume_at do
      nil -> {:created, {nil, loaded}}
      state -> {:loaded, {state, loaded}}
    end
  end

  @impl Finitomata.Persistency
  def store(_name, _payload, _transition), do: :ok
end

defmodule Finitomata.Test.PersistedListener do
  @moduledoc false

  # A persisted _FSM_ wired to the dependency-free `Finitomata.ExUnit.Listener`, used to
  #   check that `setup_finitomata/1` copes with both lifecycles a persistency can produce.

  @fsm """
  idle --> |start!| started
  started --> |do| done
  """

  use Finitomata,
    fsm: @fsm,
    listener: Finitomata.ExUnit.Listener,
    persistency: Finitomata.Test.ResumingPersistency
end
