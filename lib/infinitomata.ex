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

  ## Consistency model

  `Infinitomata` keeps a per-node view of the cluster-wide _FSM_ registry that is
    **eventually consistent**. Membership changes are propagated via `:pg` and reconciled
    by `synch/2`, which merges local and remote views (last writer wins per _FSM_ name).
    A call addressed to an _FSM_ that has not propagated to the local view yet is retried;
    on a failed remote call the node re-synchronizes and backs off before retrying. Tune
    the retry behaviour via the `:infinitomata_attempts`, `:infinitomata_poll_interval`,
    `:infinitomata_rpc_timeout`, `:infinitomata_backoff_base`, and `:infinitomata_backoff_max`
    application config keys.
  """
  @moduledoc since: "0.15.0"

  @max_attempts Application.compile_env(:finitomata, :infinitomata_attempts, 1_000)
  @rpc_timeout Application.compile_env(:finitomata, :infinitomata_rpc_timeout, 5_000)
  @poll_interval Application.compile_env(:finitomata, :infinitomata_poll_interval, 1)
  @backoff_base Application.compile_env(:finitomata, :infinitomata_backoff_base, 5)
  @backoff_max Application.compile_env(:finitomata, :infinitomata_backoff_max, 1_000)

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
               :rpc.call(node, Finitomata, fun, [id, target | args], @rpc_timeout) do
          Logger.error(
            "[♻️] Distributed: " <> inspect(id: id, node: node, target: target, error: error)
          )

          :ok = synch(id)
          backoff_sleep(attempts)
          do_distributed_call(this, fun, id, target, args, attempts - 1)
        end

      nil ->
        Process.sleep(@poll_interval)
        do_distributed_call(this, fun, id, target, args, attempts - 1)

      _ ->
        {:error, :not_started}
    end
  end

  # Exponentially backs off (with jitter, capped at `@backoff_max`) between retries that
  #   follow a failed RPC, so a struggling cluster is not hammered. The poll for a
  #   not-yet-synced FSM (the `nil` branch above) stays a tight loop because local sync
  #   usually completes near-instantly.
  defp backoff_sleep(attempts) do
    elapsed = max(0, @max_attempts - attempts)
    base = min(@backoff_max, @backoff_base * Integer.pow(2, min(elapsed, 16)))
    Process.sleep(base + :rand.uniform(max(1, div(base, 2))))
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
  # NOTE: `:rpc.block_call/5` is used deliberately (not `:erpc.call/5`). `block_call` runs the
  #   MFA in the callee's long-lived `rex` process, so a remotely started/linked `Finitomata`
  #   supervision tree survives the call; `:erpc` runs in a transient process that would take the
  #   freshly linked processes down with it.
  defp do_start_fsm(false, node, id, target, implementation, payload) do
    case :rpc.block_call(
           node,
           Finitomata,
           :start_fsm,
           [id, target, implementation, payload],
           @rpc_timeout
         ) do
      {:ok, pid} ->
        :ok = :rpc.block_call(node, :pg, :join, [InfSup.group(id), pid], @rpc_timeout)
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
