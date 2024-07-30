defmodule Finitomata.Finitomata.MyFSM do
  @moduledoc """
  `Finitomata`-based implementation of …
  """

  @fsm """
  idle --> |start| started
  started --> |finish| finished
  """

  use Finitomata, fsm: @fsm, syntax: :flowchart, auto_terminate: true

  @impl Finitomata
  def on_transition(:idle, :start, _event_payload, state) do
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :finish, _event_payload, state) do
    {:ok, :finished, state}
  end
end
