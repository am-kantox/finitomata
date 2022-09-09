defmodule Finitomata.Transition do
  @moduledoc """
  The internal representation of `Transition`.

  It includes `from` and `to` states, and the `event`, all represented as atoms.
  """

  alias Finitomata.Transition

  @typedoc "The state of FSM"
  @type state :: atom()
  @typedoc "The event in FSM"
  @type event :: atom()

  @typedoc """
  The transition is represented by `from` and `to` states _and_ the `event`.
  """
  @type t :: %{
          __struct__: Transition,
          from: state(),
          to: state(),
          event: event()
        }
  defstruct [:from, :to, :event]

  @doc false
  @spec from_parsed([binary()]) :: t()
  def from_parsed([from, to, event])
      when is_binary(from) and is_binary(to) and is_binary(event) do
    [from, to, event] =
      Enum.map(
        [from, to, event],
        &(&1 |> String.trim_leading("[") |> String.trim_trailing("]") |> String.to_atom())
      )

    %Transition{from: from, to: to, event: event}
  end

  @doc ~S"""
  Returns the state _after_ starting one, so-called `entry` state.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.entry(transitions)
      :s1
  """
  @spec entry([t()]) :: state()
  def entry(transitions) do
    transition = Enum.find(transitions, &match?(%Transition{from: :*}, &1))
    transition.to
  end

  @doc ~S"""
  Returns `true` if the transition `from` → `to` is allowed, `false` otherwise.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed?(transitions, :s1, :s2)
      true
      ...> Finitomata.Transition.allowed?(transitions, :s1, :*)
      false
  """
  @spec allowed?([t()], state(), state()) :: boolean()
  def allowed?(transitions, from, to) do
    Enum.any?(transitions, &match?(%Transition{from: ^from, to: ^to}, &1))
  end

  @doc ~S"""
  Returns `true` if the state `from` hsa an outgoing transition with `event`, false otherwise.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.responds?(transitions, :s1, :ok)
      true
      ...> Finitomata.Transition.responds?(transitions, :s1, :ko)
      false
  """
  @spec responds?([t()], state(), event()) :: boolean()
  def responds?(transitions, from, event) do
    Enum.any?(transitions, &match?(%Transition{from: ^from, event: ^event}, &1))
  end

  @doc ~S"""
  Returns the list of all the transitions, matching the options.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s3| s3")
      ...> Finitomata.Transition.allowed(transitions, to: [:idle, :*])
      [{:*, :idle, :__start__}, {:s3, :*, :__end__}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1)
      [{:s1, :s2, :to_s2}, {:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1, to: :s3)
      [{:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1, with: :to_s3)
      [{:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s2, with: :to_s2)
      []
  """
  @spec allowed([t()], [{:from, state()} | {:to, state()} | {:with, event()}]) :: [
          {state(), state(), event()}
        ]
  def allowed(transitions, options \\ []) do
    from = List.wrap(options[:from])
    to = List.wrap(options[:to])
    event = List.wrap(options[:with])

    case {from, to, event} do
      {[], [], []} ->
        for %Transition{from: from, to: to, event: event} <- transitions, do: {from, to, event}

      {fa, [], []} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            from in fa,
            do: {from, to, event}

      {[], ta, []} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            to in ta,
            do: {from, to, event}

      {[], [], ea} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            event in ea,
            do: {from, to, event}

      {fa, ta, []} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            from in fa and to in ta,
            do: {from, to, event}

      {fa, [], ea} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            from in fa and event in ea,
            do: {from, to, event}

      {[], ta, ea} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            to in ta and event in ea,
            do: {from, to, event}

      {fa, ta, ea} ->
        for %Transition{from: from, to: to, event: event} <- transitions,
            from in fa and to in ta and event in ea,
            do: {from, to, event}
    end
  end

  @doc ~S"""
  Returns the list of all the transitions, matching the `from` state and the `event`.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed(transitions, :s1, :foo)
      [:s2]
      ...> Finitomata.Transition.allowed(transitions, :s1, :*)
      []
  """
  @spec allowed([t()], state(), event()) :: [state()]
  def allowed(transitions, from, event) do
    for %Transition{from: ^from, to: to, event: ^event} <- transitions, do: to
  end

  @doc ~S"""
  Returns `Finitomata.Transition.event()` if there is a determined transition
    from the current state.

  The transition is determined, if it is the only transition allowed from the state.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s3| s3")
      ...> Finitomata.Transition.determined(transitions)
      [s3: {:__end__, :*}, s2: {:to_s3, :s3}, idle: {:to_s1, :s1}]
  """
  @spec determined([t()]) :: [{state(), {event(), state()}}]
  def determined(transitions) do
    transitions
    |> states()
    |> Enum.reduce([], fn state, acc ->
      transitions
      |> allowed(from: state)
      |> case do
        [{^state, target, event}] -> [{state, {event, target}} | acc]
        _ -> acc
      end
    end)
  end

  @doc ~S"""
  Returns `{:ok, {event(), state()}}` tuple if there is a determined transition
    from the current state, `:error` otherwise.

  The transition is determined, if it is the only transition allowed from the state.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s3| s3")
      ...> Finitomata.Transition.determined(transitions, :s1)
      :error
      iex> Finitomata.Transition.determined(transitions, :s2)
      {:ok, {:to_s3, :s3}}
      iex> Finitomata.Transition.determined(transitions, :s3)
      {:ok, {:__end__, :*}}
  """
  @spec determined([t()], state()) :: {:ok, {event(), state()}} | :error
  def determined(transitions, state) do
    transitions
    |> allowed(from: state)
    |> case do
      [{^state, target, event}] -> {:ok, {event, target}}
      _ -> :error
    end
  end

  @doc ~S"""
  Returns the not ordered list of states, excluding the starting and ending states `:*`.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.states(transitions)
      [:s1, :s2]
  """
  @spec states([t()]) :: [state()]
  def states(transitions) do
    transitions
    |> Enum.flat_map(fn %Transition{from: from, to: to} -> [from, to] end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == :*))
  end
end
