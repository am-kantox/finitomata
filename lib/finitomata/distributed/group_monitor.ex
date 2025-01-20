major = System.otp_release()

otp_version =
  try do
    {:ok, contents} = File.read(Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"]))
    String.split(contents, "\n", trim: true)
  else
    [full] -> full
    _ -> major
  catch
    :error, _ -> major
  end
  |> String.split(".")
  |> case do
    [major] -> [major, 0, 0]
    [major, minor] -> [major, minor, 0]
    [major, minor, patch | _] -> [major, minor, patch]
  end
  |> Enum.join(".")

if Version.compare(otp_version, "25.1.0") == :lt do
  defmodule Finitomata.Distributed.GroupMonitor do
    @moduledoc false
    use GenServer

    alias Finitomata.Distributed.Supervisor, as: Sup

    @update_interval Application.compile_env(:finitomata, :pg_update_interval, 500)

    def start_link(id) do
      GenServer.start_link(__MODULE__, id, name: sup_name(id))
    end

    def count(id), do: GenServer.call(sup_name(id), :count)
    def members(id), do: id |> Sup.group() |> :pg.get_members()

    defp sup_name(id), do: Module.concat(id, "GroupMonitor")

    @impl GenServer
    def init(id) do
      Process.send_after(self(), {:update, id}, @update_interval)

      {:ok, {0, MapSet.new([])}}
    end

    @impl GenServer
    def handle_info({:update, id}, {count, members}) do
      updated_members = id |> Sup.group() |> :pg.get_members() |> MapSet.new()

      joined = MapSet.difference(updated_members, members)
      handle_join(id, joined)

      left = MapSet.difference(members, updated_members)
      handle_leave(id, left)

      Process.send_after(self(), {:update, id}, @update_interval)
      {:noreply, {count, updated_members}}
    end

    defp handle_join(id, pids) do
      for pid <- pids do
        name = GenServer.call(pid, :name)
        Sup.put(id, name, %{node: :erlang.node(pid), pid: pid, ref: make_ref()})
      end
    end

    defp handle_leave(id, pids) do
      Sup.delete_by_pids(id, pids)
    end

    @impl GenServer
    def handle_call(:count, _from, {count, members}), do: {:reply, count, {count, members}}
  end
else
  defmodule Finitomata.Distributed.GroupMonitor do
    @moduledoc false
    use GenServer

    alias Finitomata.Distributed.Supervisor, as: Sup

    def start_link(id) do
      GenServer.start_link(__MODULE__, id, name: sup_name(id))
    end

    def count(id), do: GenServer.call(sup_name(id), :count)
    def members(id), do: id |> Sup.group() |> :pg.get_members()

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
    def handle_info({ref, :join, group, pids}, count) do
      {:noreply,
       Enum.reduce(pids, count, fn pid, counter ->
         id = Sup.ungroup(group)
         name = GenServer.call(pid, :name)
         Sup.put(id, name, %{node: :erlang.node(pid), pid: pid, ref: ref})
         counter + 1
       end)}
    end

    @impl GenServer
    def handle_info({_ref, :leave, group, pids}, count) do
      deleted =
        group
        |> Sup.ungroup()
        |> Sup.delete_by_pids(pids)
        |> map_size()

      {:noreply, count - deleted}
    end

    @impl GenServer
    def handle_call(:count, _from, count), do: {:reply, count, count}
  end
end
