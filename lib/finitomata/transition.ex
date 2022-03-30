defmodule Finitomata.Transition do
  @moduledoc false

  alias Finitomata.Transition

  @type state :: atom()
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
      iex> {:ok, transitions} = Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.entry(transitions)
      :s1
  """
  @spec entry([Transition.t()]) :: state()
  def entry(transitions) do
    transition = Enum.find(transitions, &match?(%Transition{from: :*}, &1))
    transition.to
  end

  @doc ~S"""
      iex> {:ok, transitions} = Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed?(transitions, :s1, :s2)
      true
      ...> Finitomata.Transition.allowed?(transitions, :s1, :*)
      false
  """
  @spec allowed?([Transition.t()], state(), state()) :: boolean()
  def allowed?(transitions, from, to) do
    not is_nil(Enum.find(transitions, &match?(%Transition{from: ^from, to: ^to}, &1)))
  end

  @doc ~S"""
      iex> {:ok, transitions} = Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.responds?(transitions, :s1, :ok)
      true
      ...> Finitomata.Transition.responds?(transitions, :s1, :ko)
      false
  """
  @spec responds?([Transition.t()], state(), event()) :: boolean()
  def responds?(transitions, from, event) do
    not is_nil(Enum.find(transitions, &match?(%Transition{from: ^from, event: ^event}, &1)))
  end

  @doc ~S"""
      iex> {:ok, transitions} = Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed(transitions, :s1, :foo)
      [:s2]
      ...> Finitomata.Transition.allowed(transitions, :s1, :*)
      []
  """
  @spec allowed([Transition.t()], state(), state()) :: [state()]
  def allowed(transitions, from, event) do
    for %Transition{from: ^from, to: to, event: ^event} <- transitions, do: to
  end

  @doc ~S"""
      iex> {:ok, transitions} = Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.states(transitions)
      [:s1, :s2]
  """
  @spec states([Transition.t()]) :: [state()]
  def states(transitions) do
    transitions
    |> Enum.flat_map(fn %Transition{from: from, to: to} -> [from, to] end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == :*))
  end
end
