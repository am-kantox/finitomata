defmodule Finitomata.Distributed.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(id) do
    Supervisor.start_link(__MODULE__, id, name: Module.concat(id, Sup))
  end

  @impl true
  def init(id) do
    children = [
      %{id: :pg, start: {:pg, :start_link, []}},
      {Finitomata, id},
      %{id: Agent, start: {Agent, :start_link, [fn -> %{} end, [name: agent(id)]]}},
      {Finitomata.Distributed.GroupMonitor, id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp agent(nil), do: agent(__MODULE__)
  defp agent(id), do: Module.concat(id, IdLookup)

  def group(nil), do: group(__MODULE__)
  def group(id), do: Module.concat(id, Group)

  def ungroup(id), do: id |> Module.split() |> Enum.slice(0..-2//1) |> Module.concat()

  def all(id), do: Agent.get(agent(id), & &1)

  def del(id, name), do: Agent.update(agent(id), &Map.delete(&1, name))

  def get(id, name), do: Agent.get(agent(id), &Map.get(&1, name))

  def select_by_pids(id, pids) when is_list(pids) do
    Agent.get(
      agent(id),
      &Map.filter(&1, fn {_, %{pid: pid}} -> pid in pids end)
    )
  end

  def delete_by_pids(id, pids) do
    {match, mismatch} =
      Agent.get(agent(id), &Map.split_with(&1, fn {_, %{pid: pid}} -> pid in pids end))

    Agent.update(agent(id), fn _ -> mismatch end)
    match
  end

  def put(id, name, %{pid: pid} = data) when is_pid(pid) do
    Agent.update(agent(id), &Map.put(&1, name, data))
  end
end
