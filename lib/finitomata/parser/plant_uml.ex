defmodule Finitomata.PlantUML do
  @moduledoc false

  import NimbleParsec
  alias Finitomata.Parser

  @behaviour Parser

  @alphanumeric [?a..?z, ?A..?Z, ?0..?9, ?_]

  blankspace = ignore(ascii_string([?\s], min: 1))
  transition_op = string("-->")
  event_op = string(":")

  event =
    ascii_char([?a..?z])
    |> optional(ascii_string(@alphanumeric, min: 1))
    |> optional(ascii_char([??, ?!]))
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
    |> ignore(choice([times(string("\n"), min: 1), times(string("\r\n"), min: 1), eos()]))
    |> tag(:transition)

  malformed =
    optional(utf8_string([not: ?\n], min: 1))
    |> string("\n")
    |> pre_traverse(:abort)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.transition("state1 --> state2 : succeeded")
      iex> result
      [transition: ["state1", "state2", "succeeded"]]

      iex> {:error, message, _, _, _, _} = Finitomata.PlantUML.transition("state1 --> State2 : succeeded")
      iex> String.slice(message, 0..14)
      "expected string"
  """
  defparsec(:transition, plant_line)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("s1 --> s2 : ok\ns2 --> [*] : ko")
      iex> result
      [transition: ["s1", "s2", "ok"], transition: ["s2", "[*]", "ko"]]
  """
  defparsec(:fsm, times(choice([plant_line, malformed]), min: 1))

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("s1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.PlantUML.validate(result)
      {:error, :initial_state}

      iex> {:ok, result, _, _, _, _} = Finitomata.PlantUML.fsm("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.PlantUML.validate(result)
      {:ok,
        [
          %Finitomata.Transition{event: :foo, from: :*, to: :s1},
          %Finitomata.Transition{event: :ok, from: :s1, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :*}
        ]}
  """
  @impl Parser
  def validate(parsed, env \\ __ENV__), do: Finitomata.validate(parsed, env)

  @doc ~S"""
      iex> Finitomata.PlantUML.parse("[*] --> s1 : ok\ns2 --> [*] : ko")
      {:error, :orphan_from_state}

      iex> Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      {:ok,
        [
          %Finitomata.Transition{event: :foo, from: :*, to: :s1},
          %Finitomata.Transition{event: :ok, from: :s1, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :*}
        ]}
  """
  @impl Parser
  def parse(input, env \\ __ENV__) do
    case fsm(input) do
      {:ok, result, _, _, _, _} ->
        validate(result, env)

      {:error, "[line: " <> _ = msg, _rest, context, _, _} ->
        [numbers, msg] = String.split(msg, "|||")
        {numbers, []} = Code.eval_string(numbers)

        {:error, msg, numbers[:content], context, {env.file, env.line, 0}, numbers[:offset]}

      error ->
        error
    end
  end

  @impl Parser
  def lint(input) when is_binary(input), do: "@startuml\n\n" <> input <> "\n@enduml"

  @spec abort(
          String.t(),
          [String.t()],
          map(),
          {non_neg_integer, non_neg_integer},
          non_neg_integer
        ) :: {:error, binary()}

  defp abort(rest, content, _context, {line, column}, offset) do
    content = content |> Enum.reverse() |> Enum.join() |> String.trim()
    meta = inspect(line: line, column: column, offset: offset, rest: rest, content: content)

    {:error,
     meta <>
       "|||malformed FSM transition (line: #{line}, column: #{column - offset}), expected `from --> to : event`"}
  end
end
