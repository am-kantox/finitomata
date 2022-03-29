defmodule Finitomata.PlantUML do
  @moduledoc false

  """
  @startuml
  scale 600 width

  [*] -> State1
  State1 --> State2 : Succeeded
  State1 --> [*] : Aborted
  State2 --> State3 : Succeeded
  State2 --> [*] : Aborted
  state State3 {
    state "Accumulate Enough Data\nLong State Name" as long1
    long1 : Just a test
    [*] --> long1
    long1 --> long1 : New Data
    long1 --> ProcessData : Enough Data
  }
  State3 --> State3 : Failed
  State3 --> [*] : Succeeded / Save Result
  State3 --> [*] : Aborted

  @enduml
  """

  import NimbleParsec

  @alphanumeric [?a..?z, ?A..?Z, ?0..?9, ?_]

  blankspace = ignore(ascii_string([?\s], min: 1))
  transition_op = string("-->")
  event_op = string(":")

  state =
    event =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> optional(ascii_string(@alphanumeric, min: 1))
    |> reduce({IO, :iodata_to_binary, []})

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

      iex> {:error, message, _, _, _, _} = Finitomata.PlantUML.transition("other stuff")
      iex> message
      "expected string \"-->\""
  """
  defparsec :transition, plant_line

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("s1 --> s2 : ok\ns2 --> s3 : ko")
      iex> result
      [transition: ["s1", "s2", "ok"], transition: ["s2", "s3", "ko"]]

      iex> {:error, message, _, _, _, _} = Finitomata.PlantUML.fsm("other stuff")
      iex> message
      "expected string \"-->\""
  """
  defparsec :fsm, times(plant_line, min: 1)
end
