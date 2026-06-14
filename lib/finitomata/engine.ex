defmodule Finitomata.Engine do
  @moduledoc false

  # Shared, process-agnostic runtime helpers used by every `use Finitomata` instance.
  #
  # Historically the whole FSM runtime was generated verbatim into each consuming module
  #   by the `use Finitomata` macro. That made the generated code huge, hard to test, and
  #   produced stacktraces pointing into macro-generated functions. This module is the seam
  #   for moving that logic into a single shared, directly unit-testable place.
  #
  # The functions here run *inside* the FSM process (they are ordinary function calls, not a
  #   separate server), therefore `self()` and the process dictionary still refer to the FSM
  #   itself. Pure helpers are extracted first; the stateful orchestration (`transit`, `init`,
  #   the `handle_*` callbacks) still lives in the generated module because it is coupled to
  #   per-module `telemetria` instrumentation and compile-time configuration.

  alias Finitomata.{State, Transition}

  @typedoc "An entry of the bounded state history; consecutive re-entries collapse into a tuple"
  @type history_entry :: Transition.state() | {Transition.state(), pos_integer()}

  @doc """
  Normalizes an auto-driven event payload into a map carrying a `__retries__` counter,
  incrementing it on every pass.

  This is used for the transitions `Finitomata` drives itself (the initial entry transition,
  `hard`/banged transitions, and `ensure_entry` retries). A non-map payload `p` becomes
  `%{payload: p, __retries__: n}`. See `c:Finitomata.on_transition/4`.

      iex> Finitomata.Engine.event_payload(:go)
      {:go, %{__retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, %{foo: :bar}})
      {:go, %{foo: :bar, __retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, 42})
      {:go, %{payload: 42, __retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, %{__retries__: 2}})
      {:go, %{__retries__: 3}}
  """
  @spec event_payload(Transition.event() | {Transition.event(), Finitomata.event_payload()}) ::
          {Transition.event(), Finitomata.event_payload()}
  def event_payload({event, %{} = payload}),
    do: {event, Map.update(payload, :__retries__, 1, &(&1 + 1))}

  def event_payload({event, payload}),
    do: event_payload({event, %{payload: payload}})

  def event_payload(event),
    do: event_payload({event, %{}})

  @doc """
  Prepends `current` to the bounded `history`, collapsing consecutive re-entries of the
  same state into a `{state, count}` tuple, and caps the result at
  `Finitomata.State.history_size/0`.

      iex> Finitomata.Engine.history(:a, [])
      [:a]
      iex> Finitomata.Engine.history(:a, [:a])
      [{:a, 2}]
      iex> Finitomata.Engine.history(:a, [{:a, 2}])
      [{:a, 3}]
      iex> Finitomata.Engine.history(:a, [:b])
      [:a, :b]
  """
  @spec history(Transition.state(), [history_entry()]) :: [history_entry()]
  def history(current, history) do
    history
    |> case do
      [^current | rest] -> [{current, 2} | rest]
      [{^current, count} | rest] -> [{current, count + 1} | rest]
      _ -> [current | history]
    end
    |> Enum.take(State.history_size())
  end
end
