defmodule ExUnitTesting do
  @moduledoc """
  The module to demonstrate testing with `Finitomata.ExUnit`.

  ```elixir
  iex|💧|1 ▸ Finitomata.start_link Foo
  {:ok, #PID<0.214.0>}

  iex|💧|2 ▸ Finitomata.start_fsm Foo, "FSM", ExUnitTesting, %ExUnitTesting{pid: self(), internals: %{counter: 0}}
  {:ok, #PID<0.226.0>}

  09:25:33.227 [debug] [→ ↹] [state: [current: :*, previous: nil]]
  09:25:33.228 [debug] [✓ ⇄] with: [current: :*, event: :__start__]
  09:25:33.228 [debug] [← ↹] [state: [current: :idle, previous: :*]]

  iex|💧|3 ▸ Finitomata.transition Foo, "FSM", {:start, self()}
  :ok

  09:25:40.577 [debug] [→ ↹] [state: [current: :idle, previous: :*]]
  09:25:40.577 [debug] [← ↹] [state: [current: :started, previous: :idle]]
 
  iex|💧|4 ▸ Finitomata.transition Foo, "FSM", :do
  :ok

  09:25:46.009 [debug] [→ ↹] [state: [current: :started, previous: :idle]]
  09:25:46.009 [debug] [← ↹] [state: [current: :done, previous: :started]]
  09:25:46.009 [debug] [→ ↹] [state: [current: :done, previous: :started]]
  09:25:46.009 [debug] [← ↹] [state: [current: :*, previous: :done]]
  09:25:46.009 [info] [◉ ↹] [state: [current: :*, previous: :done]]
  ```
  """

  @fsm """
  idle --> |start| started
  started --> |do| done
  """

  @listener (if Mix.env() == :test do
               Mox.defmock(ExUnitTesting.Mox, for: Finitomata.Listener)
               ExUnitTesting.Mox
             else
               nil
             end)

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: @listener

  defstate %{
    pid: {StreamData, :constant, [self()]},
    internals: %{counter: :integer}
  }

  # @impl Finitomata
  # def on_start(state), do: {:continue, put_in(state, [:internals, :counter], 0)}

  @impl Finitomata
  def on_transition(:idle, :start, pid, %{internals: %{counter: counter}} = state) do
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
