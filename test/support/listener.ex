Mox.defmock(Finitomata.Test.Listener.Mox, for: Finitomata.Listener)

defmodule Finitomata.Test.Listener do
  @moduledoc false

  @fsm """
  idle --> |start| started
  started --> |do| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: Finitomata.Test.Listener.Mox

  defstate(%{internals: %{pid: {StreamData, :constant, [self()]}}})

  @impl Finitomata
  def on_start(%{internals: %{pid: _pid}}), do: :ignore

  @impl Finitomata
  def on_transition(:idle, :start, event_payload, %{internals: %{pid: pid}} = state) do
    send(pid, {:on_start, event_payload})
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do, _, %{internals: %{pid: pid}} = state) do
    send(pid, :on_do)
    {:ok, :done, state}
  end

  @impl Finitomata
  def on_transition(:done, :__end__, _, %{internals: %{pid: pid}} = state) do
    send(pid, :on_end)
    {:ok, :*, state}
  end
end
