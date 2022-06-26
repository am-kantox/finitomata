defmodule Finitomata.Manager do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts \\ []),
    do: DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @impl DynamicSupervisor
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
