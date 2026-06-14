defmodule Finitomata.Error do
  @moduledoc since: "0.36.0"
  @moduledoc """
  The canonical representation of a failure that happened while processing a transition.

  Historically `Finitomata` stored the last error as an ad-hoc map and returned a handful
    of different error shapes (`{:error, atom}`, `{:error, tuple}`, keyword-tagged tuples
    like `{:error, transition: …, persistency: …}`.) This struct unifies them.

  It is intentionally a **superset** of the legacy `%{state:, event:, error:}` map, so existing
    code that reads `last_error.error`, `last_error.state` or `last_error.event`, or pattern
    matches on `%{error: …}`, keeps working. New code should prefer the canonical fields:

  - `stage` — where the failure originated (`:on_transition`, `:persistency`, …)
  - `reason` — the normalized reason (the value unwrapped from a leading `{:error, _}`)
  - `state`/`event`/`event_payload` — the transition context
  - `error` — the raw value as it was produced (kept for backward compatibility)
  - `context` — any extra information (e.g. the originating transition error for a
    persistency failure)
  """

  alias Finitomata.Transition

  @typedoc "The stage of the FSM lifecycle the error originated from"
  @type stage :: :on_transition | :persistency | :unknown

  @type t :: %__MODULE__{
          stage: stage(),
          state: Transition.state() | nil,
          event: Transition.event() | nil,
          event_payload: Finitomata.event_payload() | nil,
          reason: any(),
          error: any(),
          context: map()
        }

  defstruct stage: :unknown,
            state: nil,
            event: nil,
            event_payload: nil,
            reason: nil,
            error: nil,
            context: %{}

  @doc """
  Wraps an arbitrary transition failure into a canonical `t:Finitomata.Error.t/0`.

  `context` is a keyword list providing the transition context (`:state`, `:event`,
    `:event_payload`). Already-wrapped errors are returned untouched.
  """
  @spec wrap(any(), keyword()) :: t()
  def wrap(error, context \\ [])

  def wrap(%__MODULE__{} = error, _context), do: error

  def wrap(error, context) do
    {stage, reason, extra} = classify(error)

    [error: error, stage: stage, reason: reason, context: extra]
    |> Keyword.merge(context)
    |> then(&struct!(__MODULE__, &1))
  end

  @spec classify(any()) :: {stage(), any(), map()}
  defp classify({:error, reason}), do: classify_reason(reason)
  defp classify(reason), do: classify_reason(reason)

  @spec classify_reason(any()) :: {stage(), any(), map()}
  defp classify_reason(kw) when is_list(kw) do
    if Keyword.keyword?(kw) and Keyword.has_key?(kw, :persistency) do
      {:persistency, Keyword.get(kw, :persistency),
       kw |> Keyword.delete(:persistency) |> Map.new()}
    else
      if Keyword.keyword?(kw) and Keyword.has_key?(kw, :transition),
        do: {:on_transition, Keyword.get(kw, :transition), %{}},
        else: {:on_transition, kw, %{}}
    end
  end

  defp classify_reason(reason), do: {:on_transition, reason, %{}}
end
