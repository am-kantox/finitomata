defmodule Finitomata.Manager do
  @moduledoc false
  use DynamicSupervisor

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl DynamicSupervisor
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec fsm(module(), any(), any()) :: DynamicSupervisor.on_start_child()
  def fsm(impl, name, state) do
    DynamicSupervisor.start_child(__MODULE__, {impl, name: Finitomata.fqn(name), payload: state})
  end
end
