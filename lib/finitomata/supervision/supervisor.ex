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

  def infinitomata_name(id \\ nil), do: fq_module(id, Infinitomata, true)

  def supervisor_name(id \\ nil), do: id |> fq_module(Supervisor, true) |> uninfinitomata()
  def registry_name(id \\ nil), do: id |> fq_module(Registry, true) |> uninfinitomata()
  def manager_name(id \\ nil), do: id |> fq_module(Manager, true) |> uninfinitomata()
  def throttler_name(id \\ nil), do: id |> fq_module(Throttler, true) |> uninfinitomata()

  @spec fq_module(id :: any(), who :: any(), atomize? :: boolean()) :: module() | [any()]
  defp fq_module(id, who, false), do: [Finitomata, id, who]

  defp fq_module(id, who, true) do
    id
    |> fq_module(who, false)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&inspect/1)
    |> smart_concat()
  end

  defp uninfinitomata(mod),
    do: mod |> Module.split() |> Enum.reject(&(&1 == "Infinitomata")) |> Module.concat()

  defp smart_concat([fqn]), do: Module.concat([fqn])

  defp smart_concat([fqn, id_who]) do
    if String.starts_with?(id_who, fqn),
      do: Module.concat([id_who]),
      else: Module.concat([fqn, id_who])
  end

  defp smart_concat([fqn, id, who]) do
    if String.starts_with?(id, fqn),
      do: Module.concat([id, who]),
      else: Module.concat([fqn, id, who])
  end
end
