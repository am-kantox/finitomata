defmodule Infinitomata do
  @moduledoc """
  The sibling of `Finitomata`, but runs transparently in the cluster.
  """
  @moduledoc since: "v0.15.0"

  alias Finitomata.{ClusterInfo, State, Transition}

  @behaviour ClusterInfo

  @impl Finitomata.ClusterInfo
  @doc false
  def init(_opts \\ []) do
    Finitomata.ClusterInfo.init(__MODULE__)
  end

  @impl Finitomata.ClusterInfo
  @doc false
  def nodes, do: [node() | Node.list()]

  @impl Finitomata.ClusterInfo
  @doc false
  def whois({id, target}) do
    nodes = nodes()

    nodes
    |> :erpc.multicall(Finitomata, :lookup, [id, target])
    |> Enum.zip(nodes)
    |> Enum.find(&match?({{:ok, pid}, _node} when is_pid(pid), &1))
    |> case do
      {{:ok, pid}, node} when is_pid(pid) and is_atom(node) -> {node, pid}
      nil -> ClusterInfo.whois({id, target})
    end
  end

  defp distributed_call(fun, id, target, args) do
    {id, target}
    |> ClusterInfo.whois()
    |> case do
      {node, _pid} -> node
    end
    |> :rpc.call(Finitomata, fun, [id, target | List.wrap(args)])
    |> safe_distributed_call(fun, id, target, args)
  end

  defp safe_distributed_call({:badrpc, _}, fun, id, target, args) do
    with {node, pid} when is_pid(pid) <- whois({id, target}),
         do: :rpc.call(node, Finitomata, fun, [id, target | List.wrap(args)])
  end

  defp safe_distributed_call(value, _, _, _, _), do: value

  @doc """
  Starts the FSM somewhere in the cluster.

  See `Finitomata.start_fsm/4`.
  """
  @doc since: "0.15.0"
  @spec start_fsm(Finitomata.id(), Finitomata.fsm_name(), module(), any()) ::
          DynamicSupervisor.on_start_child()
  def start_fsm(id \\ nil, target, implementation, payload) do
    {id, target}
    |> whois()
    |> case do
      {node, pid} when is_pid(pid) and is_atom(node) ->
        {:error, {:already_started, {node, pid}}}

      _ ->
        distributed_call(:start_fsm, id, target, [implementation, payload])
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
  def transition(id \\ nil, target, event_payload, delay \\ 0),
    do: distributed_call(:transition, id, target, [event_payload, delay])

  @doc """
  The state of the FSM in the cluster.

  See `Finitomata.state/3`.
  """
  def state(id \\ nil, target, reload? \\ :full),
    do: distributed_call(:state, id, target, reload?)
end
