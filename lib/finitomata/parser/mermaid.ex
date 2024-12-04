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
  target_states = state |> concat(ignore(string(","))) |> times(min: 0) |> concat(state)
  event = ignore(string("|")) |> concat(identifier) |> ignore(string("|"))

  mermaid_line =
    optional(blankspace)
    |> concat(state)
    |> ignore(blankspace)
    |> ignore(transition_op)
    |> ignore(blankspace)
    |> concat(event)
    |> ignore(blankspace)
    |> concat(target_states)
    |> optional(blankspace)
    |> optional(semicolon)
    |> ignore(choice([times(string("\n"), min: 1), times(string("\r\n"), min: 1), eos()]))
    |> tag(:transition)

  malformed =
    optional(utf8_string([not: ?\n], min: 1))
    |> string("\n")
    |> pre_traverse(:abort)

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.transition("state1 --> |succeeded| state2")
      iex> result
      [transition: ["state1", "succeeded", "state2"]]

      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.transition("state1 --> |succeeded| state2,state3")
      iex> result
      [transition: ["state1", "succeeded", "state2", "state3"]]

      iex> {:error, message, _, _, _, _} = Finitomata.Mermaid.transition("state1 --> |succeeded| State2")
      iex> String.slice(message, 0..13)
      "expected ASCII"
  """
  defparsec(:transition, mermaid_line)

  @doc ~S"""
      iex> Finitomata.Mermaid.transitions("state1 --> |succeeded| state2,state3")
      [transition: ["state1", "succeeded", "state2"], transition: ["state1", "succeeded", "state3"]]
  """
  def transitions({:transition, [from, event | tos]}) do
    for to <- tos, do: {:transition, [from, event, to]}
  end

  def transitions(mermaid_line) do
    with {:ok, [{:transition, _ts} = transitions], _, _, _, _} <- transition(mermaid_line) do
      transitions(transitions)
    end
  end

  @doc ~S"""
      iex> "state1 --> |succeeded| state2,state3" |> Finitomata.Mermaid.transitions() |> Enum.map(&Finitomata.Mermaid.reshape_transition/1)
      [transition: ["state1", "state2", "succeeded"], transition: ["state1", "state3", "succeeded"]]
  """
  def reshape_transition({:transition, [from, event, to]}),
    do: {:transition, reshape_transition([from, event, to])}

  def reshape_transition([from, event, to]),
    do: [from, to, event]

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.do_fsm("s1 --> |ok| s2;\ns2 --> |ko| s3")
      iex> result
      [transition: ["s1", "ok", "s2"], transition: ["s2", "ko", "s3"]]
  """
  defparsec(:do_fsm, times(choice([mermaid_line, malformed]), min: 1))

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.fsm("s1 --> |ok| s2;\ns2 --> |ko| s3")
      iex> result
      [transition: ["s1", "ok", "s2"], transition: ["s2", "ko", "s3"]]
  """
  def fsm(input) when is_binary(input) do
    with {:ok, result, rest, opts, pos, count} <- do_fsm(input),
         do: {:ok, Enum.flat_map(result, &transitions/1), rest, opts, pos, count}
  end

  @doc ~S"""
      iex> {:ok, result, _, _, _, _} = Finitomata.Mermaid.fsm("s1 --> |ok| s2\ns2 --> |ko| s3")
      ...> result |> Enum.map(&Finitomata.Mermaid.reshape_transition/1) |> Finitomata.Mermaid.validate()
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

      iex> Finitomata.Mermaid.parse("s1 --> |ok| s2\ns2 --> |ko| s2,s3")
      {:ok,
        [
          %Finitomata.Transition{event: :__start__, from: :*, to: :s1},
          %Finitomata.Transition{event: :ok, from: :s1, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :s2},
          %Finitomata.Transition{event: :ko, from: :s2, to: :s3},
          %Finitomata.Transition{event: :__end__, from: :s3, to: :*}
        ]}
  """
  @impl Parser
  def parse(input, env \\ __ENV__) do
    case fsm(input) do
      {:ok, result, _, _, _, _} ->
        result
        |> Enum.map(&reshape_transition/1)
        |> validate(env)

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
    case parse(input) do
      {:ok, transitions} ->
        ["graph TD" | transitions] |> Enum.reject(&is_nil/1) |> Enum.map_join("\n    ", &dump/1)

      {:error, error} ->
        "‹ERROR› " <> inspect(error)
    end
  end

  @spec dump(Finitomata.Transition.t() | binary()) :: String.t()
  defp dump(text) when is_binary(text), do: text

  defp dump(%Finitomata.Transition{from: :*}),
    do: nil

  defp dump(%Finitomata.Transition{to: :*}),
    do: nil

  defp dump(%Finitomata.Transition{from: from, to: to, event: event}),
    do: "#{from} --> |#{event}| #{to}"

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
