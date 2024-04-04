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
    def nodes, do: HashRing.nodes(@ring)

    @impl Finitomata.ClusterInfo
    def whois(id), do: HashRing.key_to_node(@ring, id) 
  end
  ```
  """
  @moduledoc since: "0.15.0"

  require Logger

  alias Finitomata.{ClusterInfo, State, Transition}
  alias Finitomata.Distributed.GroupMonitor, as: InfMon
  alias Finitomata.Distributed.Supervisor, as: InfSup
  alias Finitomata.Supervisor, as: FinSup

  @doc since: "0.16.0"
  def start_link(id \\ nil, nodes \\ Node.list()) do
    InfSup.start_link(id, nodes)
  end

  @doc since: "0.16.0"
  def child_spec(id \\ nil) do
    Supervisor.child_spec({InfSup, id}, id: {InfSup, id})
  end

  defp distributed_call(fun, id, target, args) do
    case InfSup.get(id, target) do
      %{node: node} ->
        with {:badrpc, error} <-
               :rpc.call(node, Finitomata, fun, [id, target | List.wrap(args)]) do
          Logger.error(
            "[♻️] Distributed: " <> inspect(id: id, node: node, target: target, error: error)
          )

          :ok = synch(id)
          distributed_call(fun, id, target, args)
        end

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
  @doc "The full state with all te children, might be a heavy map"
  def all(id \\ nil) do
    id
    |> FinSup.infinitomata_name()
    |> InfSup.all()
  end

  @doc since: "0.18.0"
  @doc "Returns the random _FSM_ from the pool"
  def random(id \\ nil) do
    id
    |> FinSup.infinitomata_name()
    |> InfSup.all()
    |> Map.keys()
    |> Enum.random()
  end

  @doc since: "0.19.0"
  @doc "Synchronizes the local `Infinitomata` instance with the cluster"
  def synch(id \\ nil) do
    InfSup.synch(id, FinSup.infinitomata_name(id))
  end

  @doc """
  Starts the FSM somewhere in the cluster.

  See `Finitomata.start_fsm/4`.
  """
  @doc since: "0.15.0"
  @spec start_fsm(Finitomata.id(), Finitomata.fsm_name(), module(), any()) ::
          DynamicSupervisor.on_start_child()
  def start_fsm(id \\ nil, target, implementation, payload) do
    id = FinSup.infinitomata_name(id)

    case InfSup.get(id, target) do
      nil ->
        node = ClusterInfo.whois({id, target})

        case :rpc.block_call(node, Finitomata, :start_fsm, [id, target, implementation, payload]) do
          {:ok, pid} ->
            # local_pid = :rpc.call(node, :erlang, :list_to_pid, [:erlang.pid_to_list(pid)]).
            :ok = :rpc.block_call(node, :pg, :join, [InfSup.group(id), pid])
            {:ok, pid}

          {:badrpc, reason} ->
            {:error, reason}
        end

      %{node: node, pid: pid} ->
        {:error, {:already_started, {node, pid}}}
    end
  end

  @doc """
  Initiates the transition in the cluster.

  See `Finitomata.transition/4`.
  """
  @doc since: "0.15.0"
  @spec transition(
          Finitomata.id(),
          Finitomata.fsm_name(),
          Transition.event() | {Transition.event(), State.payload()},
          non_neg_integer()
        ) ::
          :ok
  def transition(id \\ nil, target, event_payload, delay \\ 0) do
    id = FinSup.infinitomata_name(id)
    distributed_call(:transition, id, target, [event_payload, delay])
  end

  @doc """
  The state of the FSM in the cluster.

  See `Finitomata.state/3`.
  """
  @doc since: "0.15.0"
  def state(id \\ nil, target, reload? \\ :full) do
    id = FinSup.infinitomata_name(id)
    distributed_call(:state, id, target, reload?)
  end
end
