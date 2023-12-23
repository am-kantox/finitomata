defmodule Finitomata.Mermaid do
  @moduledoc false

  import NimbleParsec
  alias Finitomata.Parser

  @behaviour Parser

  @alphanumeric [?a..?z, ?A..?Z, ?0..?9, ?_]

  blankspace = ignore(ascii_string([?\s], min: 1))
  semicolon = ignore(string(";"))
  transition_op = string("-->")

  identifier =
    ascii_char([?a..?z])
    |> optional(ascii_string(@alphanumeric, min: 1))
    |> optional(ascii_char([??, ?!]))
    |> reduce({IO, :iodata_to_binary, []})

  state = identifier
  event = ignore(string("|")) |> concat(identifier) |> ignore(string("|"))

  mermaid_line =
    optional(blankspace)
    |> concat(state)
    |> ignore(blankspace)
    |> ignore(transition_op)
    |> ignore(blankspace)
    |> concat(event)
    |> ignore(blankspace)
    |> concat(state)
    |> optional(blankspace)
    |> optional(semicolon)
    |> ignore(choice([times(string("\n"), min: 1), eos()]))
    |> tag(:transition)

  malformed =
    optional(utf8_string([not: ?\n], min: 1))
    |> string("\n")
    |> pre_traverse(:abort)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.transition("state1 --> |succeeded| state2")
      iex> result
      [transition: ["state1", "succeeded", "state2"]]

      iex> {:error, message, _, _, _, _} = Finitomata.Mermaid.transition("state1 --> |succeeded| State2")
      iex> String.slice(message, 0..13)
      "expected ASCII"
  """
  defparsec(:transition, mermaid_line)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.fsm("s1 --> |ok| s2;\ns2 --> |ko| s3")
      iex> result
      [transition: ["s1", "ok", "s2"], transition: ["s2", "ko", "s3"]]
  """
  defparsec(:fsm, times(choice([mermaid_line, malformed]), min: 1))

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.fsm("s1 --> |ok| s2\ns2 --> |ko| s3")
      ...> Finitomata.Mermaid.validate(result)
      {:ok,
        [
          %Finitomata.Transition{event: :__start__, from: :*, to: :s1},
          %Finitomata.Transition{event: :ok, from: :s1, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :s3},
          %Finitomata.Transition{event: :__end__, from: :s3, to: :*}
        ]}
  """
  @impl Parser
  def validate(parsed, env \\ __ENV__) do
    parsed =
      Enum.map(parsed, fn {:transition, [from, event, to]} -> {:transition, [from, to, event]} end)

    from_states = parsed |> Enum.map(fn {:transition, [from, _, _]} -> from end) |> Enum.uniq()
    to_states = parsed |> Enum.map(fn {:transition, [_, to, _]} -> to end) |> Enum.uniq()

    start_states =
      Enum.map(from_states -- to_states, fn from -> {:transition, ["[*]", from, "__start__"]} end)

    final_states =
      Enum.map(to_states -- from_states, fn to -> {:transition, [to, "[*]", "__end__"]} end)

    amended = start_states ++ parsed ++ final_states

    Finitomata.validate(amended, env)
  end

  @doc ~S"""
      iex> Finitomata.Mermaid.parse("s1 --> |ok| s2\ns2 --> |ko| s3")
      {:ok,
        [
          %Finitomata.Transition{event: :__start__, from: :*, to: :s1},
          %Finitomata.Transition{event: :ok, from: :s1, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :s3},
          %Finitomata.Transition{event: :__end__, from: :s3, to: :*}
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
  def lint(input) when is_binary(input) do
    input = input |> String.split("\n", trim: true) |> Enum.map_join("\n", &("    " <> &1))

    "graph TD\n" <> input
  end

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
       "|||malformed FSM transition (line: #{line}, column: #{column - offset}), expected `from --> |event| to`"}
  end
end
