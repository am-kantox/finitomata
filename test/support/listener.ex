Mox.defmock(Finitomata.Test.Listener.Mox, for: Finitomata.Listener)

defmodule Finitomata.Test.Listener do
  @moduledoc false

  @fsm """
  idle --> |start| started
  started --> |do| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: Finitomata.Test.Listener.Mox

  defstruct pid: nil

  @impl Finitomata
  def on_start(%__MODULE__{pid: _pid}), do: :ignore

  @impl Finitomata
  def on_transition(:idle, :start, event_payload, %__MODULE__{pid: pid} = state) do
    send(pid, {:on_start, event_payload})
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do, _, %__MODULE__{pid: pid} = state) do
    send(pid, :on_do)
    {:ok, :done, state}
  end

  @impl Finitomata
  def on_transition(:done, :__end__, _, %__MODULE__{pid: pid} = state) do
    send(pid, :on_end)
    {:ok, :*, state}
  end
end
