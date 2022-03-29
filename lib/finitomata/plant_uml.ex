defmodule Finitomata.PlantUML do
  @moduledoc false

  defmodule Transition do
    @moduledoc false

    @type t :: %{
            from: binary(),
            to: binary(),
            event: binary()
          }
    defstruct [:from, :to, :event]

    def from_parsed([from, to, event]) do
      struct(Transition, from: from, to: to, event: event)
    end
  end

  import NimbleParsec

  @alphanumeric [?a..?z, ?A..?Z, ?0..?9, ?_]

  blankspace = ignore(ascii_string([?\s], min: 1))
  transition_op = string("-->")
  event_op = string(":")

  event =
    ascii_char([?a..?z])
    |> optional(ascii_string(@alphanumeric, min: 1))
    |> reduce({IO, :iodata_to_binary, []})

  state = choice([string("[*]"), event])

  plant_line =
    optional(blankspace)
    |> concat(state)
    |> ignore(blankspace)
    |> ignore(transition_op)
    |> ignore(blankspace)
    |> concat(state)
    |> ignore(blankspace)
    |> ignore(event_op)
    |> ignore(blankspace)
    |> concat(event)
    |> optional(blankspace)
    |> ignore(choice([string("\n"), eos()]))
    |> tag(:transition)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.transition("state1 --> state2 : succeeded")
      iex> result
      [transition: ["state1", "state2", "succeeded"]]

      iex> {:error, message, _, _, _, _} = Finitomata.PlantUML.transition("state1 --> State2 : succeeded")
      iex> String.slice(message, 0..14)
      "expected string"
  """
  defparsec :transition, plant_line

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("s1 --> s2 : ok\ns2 --> [*] : ko")
      iex> result
      [transition: ["s1", "s2", "ok"], transition: ["s2", "[*]", "ko"]]
  """
  defparsec :fsm, times(plant_line, min: 1)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("s1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.PlantUML.validate(result)
      {:error, :initial_state}

      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.PlantUML.validate(result)
      {:ok,
        [
          %Finitomata.PlantUML.Transition{event: "foo", from: "[*]", to: "s1"},
          %Finitomata.PlantUML.Transition{event: "ok", from: "s1", to: "s2"},
          %Finitomata.PlantUML.Transition{event: "ko", from: "s2", to: "[*]"}
        ]}
  """
  @spec validate([{:transition, [binary()]}]) :: {:ok, [Transition.t()]} | {:error, any()}
  def validate(parsed) do
    from_states = parsed |> Enum.map(fn {:transition, [from, _, _]} -> from end) |> Enum.uniq()
    to_states = parsed |> Enum.map(fn {:transition, [_, to, _]} -> to end) |> Enum.uniq()

    cond do
      Enum.count(parsed, &match?({:transition, ["[*]", _, _]}, &1)) != 1 ->
        {:error, :initial_state}

      Enum.count(parsed, &match?({:transition, [_, "[*]", _]}, &1)) < 1 ->
        {:error, :final_state}

      from_states -- to_states != [] ->
        {:error, :orphan_from_state}

      to_states -- from_states != [] ->
        {:error, :orphan_to_state}

      true ->
        {:ok, Enum.map(parsed, &(&1 |> elem(1) |> Transition.from_parsed()))}
    end
  end
end
