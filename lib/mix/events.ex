defmodule Finitomata.Mix.Events do
  @moduledoc false

  use Boundary, deps: [], exports: []

  use Agent

  def start_link,
    do: Agent.start_link(fn -> %{events: %{}, diagnostics: MapSet.new()} end, name: __MODULE__)

  def all, do: Agent.get(__MODULE__, & &1)

  def put(:event, {module, event}) do
    Agent.update(
      __MODULE__,
      &update_in(&1, [:events, module], fn
        nil -> MapSet.new([event])
        events -> MapSet.put(events, event)
      end)
    )
  end

  def put(:diagnostic, diagnostic),
    do:
      Agent.update(
        __MODULE__,
        &Map.update!(&1, :diagnostics, fn diagnostics -> MapSet.put(diagnostics, diagnostic) end)
      )
end
