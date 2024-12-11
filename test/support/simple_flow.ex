defmodule Finitomata.Test.Flow do
  @moduledoc false

  defmodule SubFlow1 do
    @moduledoc """
    SubFlow Example
    """
    use Finitomata.Flow, flow: "priv/flows/sf1.flow"
  end

  @fsm """
  s1 --> |to_s2| s2 
  s2 --> |to_s3| s3 
  """

  # use Finitomata, fsm: @fsm, forks: [s2: Finitomata.SimpleFlow.create(@sf1)]

  # - `SimpleFlow.create/2` injects a callback (message) to the parent process once finished
  # - if the textual representation is specified, it’ll be cached as a module,
  #     and reloaded in a runtime if changed
  use Finitomata, fsm: @fsm, forks: [s2: [{SubFlow1, :to_s3}]]

  @impl Finitomata
  def on_transition(:s1, :to_s2, event_payload, state_payload) do
    Logger.info(
      "[✓ ⇄] with: " <>
        inspect(
          event_payload: event_payload,
          state: state_payload
        )
    )

    {:ok, :s2, state_payload}
  end
end
