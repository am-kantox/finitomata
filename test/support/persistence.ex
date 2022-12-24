defmodule Finitomata.Test.Persistency do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |do!| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, persistency: Finitomata.Persistency.Protocol

  defstruct pid: nil

  @impl Finitomata
  def on_transition(:idle, :start!, _, %__MODULE__{pid: pid} = state) do
    send(pid, :on_start!)
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do!, _, %__MODULE__{pid: pid} = state) do
    send(pid, :on_do!)
    {:ok, :done, state}
  end

  @impl Finitomata
  def on_transition(:done, :__end__, _, %__MODULE__{pid: pid} = state) do
    send(pid, :on_end)
    {:ok, :*, state}
  end
end

defimpl Finitomata.Persistency.Persistable, for: Finitomata.Test.Persistency do
  @moduledoc false
  require Logger

  def load(data, name) do
    Logger.debug("[LOAD] " <> inspect({name, data}))
    data
  end

  def store(data, name, updated_data, supplemental_data) do
    Logger.debug("[STORE] " <> inspect({name, data, updated_data, supplemental_data}))
  end

  def store_error(data, name, reason, supplemental_data) do
    Logger.debug("[STORE ERROR] " <> inspect({name, data, reason, supplemental_data}))
  end
end
