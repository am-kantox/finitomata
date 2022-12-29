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

  def load(data) do
    Logger.debug(inspect(data, label: "[LOAD]"))
    {:unknown, data}
  end

  def store(data, info) do
    Logger.debug("[STORE] " <> inspect({data, info}))
  end

  def store_error(data, reason, info) do
    Logger.debug("[STORE ERROR] " <> inspect({data, reason, info}))
  end
end
