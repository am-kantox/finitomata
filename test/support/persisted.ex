defmodule Finitomata.Test.PersistedData do
  @moduledoc false
  # Carried payload for the persistence-adapter fixtures. It deliberately has no `:id`
  #   field, so `Finitomata.Engine` injects the FSM name as the storage id.
  defstruct value: 0
end

defmodule Finitomata.Test.PersistedETS do
  @moduledoc false

  @fsm """
  idle --> |bump| counted
  counted --> |bump| counted
  counted --> |boom| counted
  counted --> |stop| stopped
  """

  use Finitomata, fsm: @fsm, persistency: Finitomata.Persistency.ETS

  alias Finitomata.Test.PersistedData

  @impl Finitomata
  def on_transition(:idle, :bump, _payload, %PersistedData{value: value} = data),
    do: {:ok, :counted, %PersistedData{data | value: value + 1}}

  def on_transition(:counted, :bump, _payload, %PersistedData{value: value} = data),
    do: {:ok, :counted, %PersistedData{data | value: value + 1}}

  def on_transition(:counted, :boom, _payload, _data),
    do: {:error, :boom}

  def on_transition(:counted, :stop, _payload, data),
    do: {:ok, :stopped, data}
end

defmodule Finitomata.Test.PersistedDETS do
  @moduledoc false

  @fsm """
  idle --> |bump| counted
  counted --> |bump| counted
  counted --> |stop| stopped
  """

  use Finitomata, fsm: @fsm, persistency: Finitomata.Persistency.DETS

  alias Finitomata.Test.PersistedData

  @impl Finitomata
  def on_transition(:idle, :bump, _payload, %PersistedData{value: value} = data),
    do: {:ok, :counted, %PersistedData{data | value: value + 1}}

  def on_transition(:counted, :bump, _payload, %PersistedData{value: value} = data),
    do: {:ok, :counted, %PersistedData{data | value: value + 1}}

  def on_transition(:counted, :stop, _payload, data),
    do: {:ok, :stopped, data}
end
