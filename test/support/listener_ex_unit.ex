defmodule Finitomata.Test.ListenerExUnit do
  @moduledoc false

  # Mirrors `Finitomata.Test.Listener`, but wired to the dependency-free
  #   `Finitomata.ExUnit.Listener` instead of `:mox`, and with a soft `reject?` event used
  #   to exercise `Finitomata.ExUnit.assert_no_transition/3`.

  @fsm """
  idle --> |start| started
  started --> |reject?| started
  started --> |do| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: Finitomata.ExUnit.Listener

  defstate %{internals: %{counter: :integer}}

  @impl Finitomata
  def on_start(state), do: {:continue, put_in(state, [:internals, :counter], 0)}

  @impl Finitomata
  def on_transition(:idle, :start, _payload, %{internals: %{counter: counter}} = state),
    do: {:ok, :started, %{state | internals: %{counter: counter + 1}}}

  @impl Finitomata
  def on_transition(:started, :reject?, _payload, _state),
    do: {:error, :rejected}

  @impl Finitomata
  def on_transition(:started, :do, _payload, state),
    do: {:ok, :done, update_in(state, [:internals, :counter], &(&1 + 1))}

  @impl Finitomata
  def on_transition(:done, :__end__, _payload, state),
    do: {:ok, :*, state}
end
