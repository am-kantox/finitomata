defmodule Finitomata.Transition do
  @moduledoc false

  @type t :: %{
          from: atom(),
          to: atom(),
          event: atom()
        }
  defstruct [:from, :to, :event]

  def from_parsed([from, to, event]) do
    [from, to, event] =
      Enum.map(
        [from, to, event],
        &(&1 |> String.trim_leading("[") |> String.trim_trailing("]") |> String.to_atom())
      )

    struct(Finitomata.Transition, from: from, to: to, event: event)
  end
end
