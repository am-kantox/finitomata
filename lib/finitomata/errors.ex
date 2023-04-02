defmodule Finitomata.TestTransitionError do
  defexception path: nil, transition: nil, missing_states: [], unknown_states: [], message: nil

  @impl true
  def message(%{message: nil} = exception) do
    Enum.join(
      [
        "The transition validation must include all possible continuations.",
        "  Transition: " <> inspect(exception.transition) <> ".",
        "  Missing states: " <> inspect(exception.missing_states) <> ".",
        "  Unknown states: " <> inspect(exception.unknown_states) <> "."
      ],
      "\n"
    )
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
    "\nIf you do not want to validate anything after entering some states, use " <>
      "`:state -> :ok` clause.\n"
  end
end
