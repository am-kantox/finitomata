defmodule Finitomata.Test.Listener do
  @moduledoc false

  @fsm """
  idle --> |start| started
  started --> |do| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: :mox

  defstate %{
    pid: {StreamData, :constant, [self()]},
    internals: %{counter: :integer}
  }

  @impl Finitomata
  def on_start(state), do: {:continue, put_in(state, [:internals, :counter], 0)}

  @impl Finitomata
  def on_transition(:idle, :start, pid, %{internals: %{counter: counter}} = state) do
    send(pid, {:on_start, pid})
    state = %{state | pid: pid, internals: %{counter: counter + 1}}
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do, _, %{pid: pid} = state) do
    send(pid, :on_do)
    {:ok, :done, update_in(state, [:internals, :counter], &(&1 + 1))}
  end

  @impl Finitomata
  def on_transition(:done, :__end__, _, %{pid: pid} = state) do
    send(pid, :on_end)
    {:ok, :*, state}
  end
end
