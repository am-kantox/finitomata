defmodule Finitomata.Test.Flow do
  @moduledoc false

  defmodule SubFlow1 do
    @moduledoc false
    use Finitomata.Flow, flow: "priv/flows/sf1.flow"

    def finalize(params, id, object) do
      require Logger

      Logger.warning(
        "Implementation for finalize is here with args " <>
          inspect(params: params, id: id, object: object)
      )
    end
  end

  defmodule SubFlow2 do
    @moduledoc false
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
  use Finitomata, fsm: @fsm, forks: [s2: [to_s3: SubFlow1, to_s3: SubFlow2]]

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

  @impl Finitomata
  def on_fork(:s2, _state_payload) do
    {:ok, SubFlow1}
  end
end

defmodule Foo.Bar do
  @moduledoc false
  def recipient_flow_name(_, _, _), do: :recipient_flow_name
end
