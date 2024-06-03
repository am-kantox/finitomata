defmodule Finitomata.Distributed.Supervisor do
  @moduledoc false

  require Logger

  use Supervisor

  def start_link(id, nodes \\ Node.list()) do
    __MODULE__
    |> Supervisor.start_link(id, name: sup_name(id))
    |> tap(fn
      {:ok, pid} when is_pid(pid) ->
        Enum.each(nodes, fn node ->
          with {:badrpc, error} <- :rpc.block_call(node, __MODULE__, :start_link, [id, []]) do
            Logger.error(
              "[♻️] Remote start: " <>
                inspect(id: id, name: sup_name(id), node: node, error: error)
            )
          end
        end)

        Task.start(fn -> synch(id) end)

      other ->
        other
    end)
  end

  @impl true
  def init(id) do
    id = Finitomata.Supervisor.infinitomata_name(id)

    children = [
      %{id: {:pg, id}, start: {__MODULE__, :start_pg, []}},
      {Finitomata, id},
      %{id: {Agent, id}, start: {Agent, :start_link, [fn -> %{} end, [name: agent(id)]]}},
      {Finitomata.Distributed.GroupMonitor, id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp sup_name(id), do: id |> Finitomata.Supervisor.infinitomata_name() |> Module.concat(Sup)

  defp agent(nil), do: agent(__MODULE__)
  defp agent(id), do: Module.concat(id, IdLookup)

  def group(nil), do: group(__MODULE__)
  def group(id), do: Module.concat(id, Group)

  def ungroup(id), do: id |> Module.split() |> Enum.slice(0..-2//1) |> Module.concat()

  def synch(id, fqn_id \\ nil) do
    fqn_id = if is_nil(fqn_id), do: Finitomata.Supervisor.infinitomata_name(id), else: fqn_id
    known_processes_alive = fqn_id |> group() |> :pg.get_members()
    domestic = Map.new(Infinitomata.all(id), &fix_pid(&1, known_processes_alive))

    known_fsms_alive = fn _ ->
      merger =
        fn _k, %{node: node, pid: pid}, %{node: node, pid: pid} ->
          %{node: node, pid: pid, ref: make_ref()}
        end

      call_handler = fn result, id, node ->
        with {:badrpc, error} <- result do
          Logger.warning("[♻️] Synch Error: " <> inspect(id: id, node: node, error: error))
          []
        end
      end

      Enum.reduce(Node.list(), domestic, fn node, acc ->
        node
        |> :rpc.block_call(Infinitomata, :all, [id])
        |> call_handler.(id, node)
        |> Map.new(&fix_pid(&1, known_processes_alive))
        |> Map.merge(acc, merger)
      end)
    end

    fqn_id |> agent() |> Agent.update(known_fsms_alive)
  end

  def all(id) do
    with empty when empty == %{} <- Agent.get(agent(id), & &1) do
      Logger.error("[♻️] Empty pool for ‹#{inspect(id)}›")
      %{}
    end
  end

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
      Agent.get(agent(id), &split_with(&1, fn {_, %{pid: pid}} -> pid in pids end))

    Agent.update(agent(id), fn _ -> mismatch end)
    match
  end

  def put(id, name, %{pid: pid} = data) when is_pid(pid) do
    Agent.update(agent(id), &Map.put(&1, name, data))
  end

  defp skip_node(nil), do: nil
  defp skip_node(pid) when is_pid(pid), do: pid |> :erlang.pid_to_list() |> skip_node()
  defp skip_node([?. | tail]), do: tail
  defp skip_node([_ | tail]), do: skip_node(tail)

  defp fix_pid({name, %{pid: pid} = value}, pids),
    do: {name, %{value | pid: fix_pid(pid, pids)}}

  defp fix_pid(pid, pids) do
    pid_tail = skip_node(pid)

    Enum.find(pids, &(skip_node(&1) == pid_tail))
  end

  if Version.compare(System.version(), "1.15.0") == :lt do
    defp split_with(%{} = map, fun) when is_function(fun, 1) do
      {truthy, falsey} = Enum.split_with(map, fun)
      {Map.new(truthy), Map.new(falsey)}
    end
  else
    defdelegate split_with(map, fun), to: Map
  end

  @doc false
  def start_pg do
    with {:error, {:already_started, pid}} <- :pg.start_link(), do: :ignore
  end
end
