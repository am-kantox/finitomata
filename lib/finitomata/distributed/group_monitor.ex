defmodule Finitomata.Distributed.GroupMonitor do
  @moduledoc false
  use GenServer

  alias Finitomata.Distributed.Supervisor, as: Sup

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: sup_name(id))
  end

  def count(id), do: GenServer.call(sup_name(id), :count)

  defp sup_name(id), do: Module.concat(id, "GroupMonitor")

  @impl GenServer
  def init(id) do
    {_reference, _pids} =
      id
      |> Sup.group()
      |> :pg.monitor()

    {:ok, 0}
  end

  @impl GenServer
  def handle_info({ref, :join, group, pids}, counter) do
    {:noreply,
     Enum.reduce(pids, counter, fn pid, counter ->
       id = Sup.ungroup(group)
       name = GenServer.call(pid, :name)
       Sup.put(id, name, %{node: :erlang.node(pid), pid: pid, ref: ref})
       counter + 1
     end)}
  end

  @impl GenServer
  def handle_info({_ref, :leave, group, pids}, counter) do
    deleted =
      group
      |> Sup.ungroup()
      |> Sup.delete_by_pids(pids)
      |> map_size()

    {:noreply, counter - deleted}
  end

  @impl GenServer
  def handle_call(:count, _from, state), do: {:reply, state, state}
end
