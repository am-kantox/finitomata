defmodule Finitomata.TestTransitionError do
  defexception path: nil, transition: [], missing_states: [], unknown_states: [], message: nil

  @impl true
  def message(%{message: nil} = exception) do
    [
      "The transition validation must include all possible continuations.",
      if(not Enum.empty?(exception.transition),
        do: "  Transition: " <> inspect(exception.transition) <> "."
      ),
      if(not Enum.empty?(exception.missing_states),
        do: "  Missing states: " <> inspect(exception.missing_states) <> "."
      ),
      if(not Enum.empty?(exception.unknown_states),
        do: "  Unknown states: " <> inspect(exception.unknown_states) <> "."
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def message(%{message: message}) do
    message
  end

  @impl true
  def blame(exception, stacktrace) do
    message = message(exception) <> hint()
    {%{exception | message: message}, stacktrace}
  end

  defp hint do
    [
      :yellow,
      "\n  💡 If you do not want to validate anything after entering some states, use " <>
        "`{:event, payload} -> :ok` clause.\n"
    ]
    |> IO.ANSI.format()
    |> to_string()
  end
end
