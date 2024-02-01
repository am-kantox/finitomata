defmodule Finitomata.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(id \\ nil)
  def start_link([]), do: start_link(nil)
  def start_link(id: id), do: start_link(id)

  def start_link(id),
    do: Supervisor.start_link(__MODULE__, id, name: supervisor_name(id))

  @impl Supervisor
  def init(id) do
    children = [
      {Registry, keys: :unique, name: registry_name(id), partitions: System.schedulers_online()},
      {Finitomata.Manager, name: manager_name(id)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def supervisor_name(id \\ nil), do: fq_module(id, Supervisor, true)
  def registry_name(id \\ nil), do: fq_module(id, Registry, true)
  def manager_name(id \\ nil), do: fq_module(id, Manager, true)
  def infinitomata_name(id \\ nil), do: fq_module(id, Infinitomata, true)
  def throttler_name(id \\ nil), do: fq_module(id, Throttler, true)

  @spec fq_module(id :: any(), who :: any(), atomize? :: boolean()) :: module() | [any()]
  defp fq_module(id, who, false), do: [Finitomata, id, who]

  defp fq_module(id, who, true) do
    id
    |> fq_module(who, false)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&inspect/1)
    |> Module.concat()
  end
end
