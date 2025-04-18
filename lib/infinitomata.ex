defmodule Infinitomata do
  @moduledoc """
  The sibling of `Finitomata`, but runs transparently in the cluster.

  If you want to use a _stateful consistent hash ring_ like [`libring`](https://hexdocs.pm/libring),
    implement the behaviour `Finitomata.ClusterInfo` wrapping calls to it and 
    invoke `Finitomata.ClusterInfo.init(Impl)` before using `Infinitomata.start_fsm/4`.

  The example of such an implementation for `libring` (assuming the named ring `@ring`
    has been started in the supervision tree) follows.

  ```elixir
  defmodule MyApp.ClusterInfo do
    @moduledoc false
    @behaviour Finitomata.ClusterInfo

    @impl Finitomata.ClusterInfo
    def nodes(_fini_id), do: HashRing.nodes(@ring) -- [node()]

    @impl Finitomata.ClusterInfo
    def whois(_fini_id, id), do: HashRing.key_to_node(@ring, id)
  end
  ```
  """
  @moduledoc since: "0.15.0"

  @max_attempts Application.compile_env(:finitomata, :infinitomata_attempts, 1_000)

  require Logger

  alias Finitomata.{ClusterInfo, State, Transition}
  alias Finitomata.Distributed.GroupMonitor, as: InfMon
  alias Finitomata.Distributed.Supervisor, as: InfSup
  alias Finitomata.Supervisor, as: FinSup

  @behaviour Finitomata.Supervisor

  @doc since: "0.16.0"
  def start_link(id \\ nil, nodes \\ Node.list()) do
    InfSup.start_link(id, nodes)
  end

  @doc since: "0.16.0"
  @impl Finitomata.Supervisor
  def child_spec(id \\ nil) do
    Supervisor.child_spec({InfSup, id}, id: {InfSup, id})
  end

  defp distributed_call(fun, id, target, args \\ []) do
    do_distributed_call(node(), fun, FinSup.infinitomata_name(id), target, args, @max_attempts)
  end

  defp do_distributed_call(:nonode@nohost, fun, id, target, args, _attempts) do
    apply(Finitomata, fun, [id, target | args])
  end

  defp do_distributed_call(_this, _fun, _id, _target, _args, 0), do: {:error, :exhausted}

  defp do_distributed_call(this, fun, id, target, args, attempts) do
    case InfSup.get(id, target) do
      %{node: node} ->
        with {:badrpc, error} <-
               :rpc.call(node, Finitomata, fun, [id, target | args]) do
          Logger.error(
            "[♻️] Distributed: " <> inspect(id: id, node: node, target: target, error: error)
          )

          :ok = synch(id)
          do_distributed_call(this, fun, id, target, args, attempts - 1)
        end

      nil ->
        Process.sleep(1)
        do_distributed_call(this, fun, id, target, args, attempts - 1)

      _ ->
        {:error, :not_started}
    end
  end

  @doc since: "0.16.0"
  @doc "Count of children"
  def count(id \\ nil) do
    id
    |> FinSup.infinitomata_name()
    |> InfMon.count()
  end

  @doc since: "0.16.0"
  @impl Finitomata.Supervisor
  @spec all(Finitomata.id()) :: %{
          optional(Finitomata.fsm_name()) => %{pid: pid(), node: node(), reference: reference()}
        }
  def all(id \\ nil) do
    id
    |> FinSup.infinitomata_name()
    |> InfSup.all()
  end

  @doc since: "0.18.0"
  @doc "Returns the random _FSM_ from the pool"
  def random(id \\ nil) do
    id
    |> all()
    |> Map.keys()
    |> case do
      [] ->
        Process.sleep(200)
        random(id)

      [_ | _] = nodes ->
        Enum.random(nodes)
    end
  end

  @doc since: "0.19.0"
  @doc "Synchronizes the local `Infinitomata` instance with the cluster"
  @spec synch(Finitomata.id(), [node()] | false) :: :ok
  def synch(id \\ nil, nodes \\ false)

  def synch(id, false) do
    InfSup.synch(id, ClusterInfo.nodes(id), FinSup.infinitomata_name(id))
  end

  def synch(id, nodes) when is_list(nodes) do
    InfSup.synch(id, nodes, FinSup.infinitomata_name(id))
  end

  @doc since: "0.15.0"
  @doc """
  Starts the _FSM_ in the distributed environment. See `Finitomata.start_fsm/4` for docs and options
  """
  @impl Finitomata.Supervisor
  @spec start_fsm(Finitomata.id(), Finitomata.fsm_name(), module(), any()) ::
          DynamicSupervisor.on_start_child()
  def start_fsm(fini_id \\ nil, target, implementation, payload) do
    id = FinSup.infinitomata_name(fini_id)

    case InfSup.get(id, target) do
      nil ->
        node = ClusterInfo.whois(fini_id, {id, target})
        do_start_fsm(node == node(), node, id, target, implementation, payload)

      %{node: node, pid: pid} ->
        {:error, {:already_started, {node, pid}}}
    end
  end

  @spec do_start_fsm(boolean(), node(), Finitomata.id(), Finitomata.fsm_name(), module(), any()) ::
          DynamicSupervisor.on_start_child()
  defp do_start_fsm(false, node, id, target, implementation, payload) do
    case :rpc.block_call(node, Finitomata, :start_fsm, [id, target, implementation, payload]) do
      {:ok, pid} ->
        # local_pid = :rpc.call(node, :erlang, :list_to_pid, [:erlang.pid_to_list(pid)]).
        :ok = :rpc.block_call(node, :pg, :join, [InfSup.group(id), pid])
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:error, {:already_started, {node, pid}}}

      {error, reason} when error in [:error, :badrpc] ->
        {:error, reason}
    end
  end

  defp do_start_fsm(true, node, id, target, implementation, payload) do
    case Finitomata.start_fsm(id, target, implementation, payload) do
      {:ok, pid} ->
        :ok = :pg.join(InfSup.group(id), pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:error, {:already_started, {node, pid}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc since: "0.19.0"
  @impl Finitomata.Supervisor
  @spec timer_tick(Finitomata.id(), Finitomata.fsm_name()) :: :ok
  def timer_tick(id \\ nil, target) do
    distributed_call(:timer_tick, id, target)
  end

  @doc since: "0.15.0"
  @impl Finitomata.Supervisor
  @spec transition(
          Finitomata.id(),
          Finitomata.fsm_name(),
          Transition.event() | {Transition.event(), State.payload()},
          non_neg_integer()
        ) ::
          :ok
  def transition(id \\ nil, target, event_payload, delay \\ 0) do
    distributed_call(:transition, id, target, [event_payload, delay])
  end

  @doc since: "0.15.0"
  @impl Finitomata.Supervisor
  def state(id \\ nil, target, reload? \\ :full) do
    distributed_call(:state, id, target, [reload?])
  end

  @doc since: "0.26.0"
  @impl Finitomata.Supervisor
  def alive?(id \\ nil, target) do
    distributed_call(:alive?, id, target)
  end
end
