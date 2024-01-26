defmodule Infinitomata do
  @moduledoc """
  The sibling of `Finitomata`, but runs transparently in the cluster.
  """
  @moduledoc since: "v0.15.0"

  alias Finitomata.{ClusterInfo, State, Transition}
  alias Finitomata.Distributed.Supervisor, as: Sup

  def start_link(id \\ __MODULE__) do
    Sup.start_link(id)
  end

  def child_spec(id \\ __MODULE__) do
    Supervisor.child_spec({Sup, id}, id: {Sup, id})
  end

  defp distributed_call(fun, id, target, args) do
    case Sup.get(id, target) do
      %{node: node} ->
        :rpc.call(node, Finitomata, fun, [id, target | List.wrap(args)])

      _ ->
        {:error, :not_started}
    end
  end

  @doc """
  Starts the FSM somewhere in the cluster.

  See `Finitomata.start_fsm/4`.
  """
  @doc since: "0.15.0"
  @spec start_fsm(Finitomata.id(), Finitomata.fsm_name(), module(), any()) ::
          DynamicSupervisor.on_start_child()
  def start_fsm(id \\ nil, target, implementation, payload) do
    case Sup.get(id, target) do
      nil ->
        {node, nil} = ClusterInfo.whois({id, target})

        case :rpc.call(node, Finitomata, :start_fsm, [id, target, implementation, payload]) do
          {:ok, pid} ->
            :pg.join(Sup.group(id), pid)
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
  def transition(id \\ nil, target, event_payload, delay \\ 0),
    do: distributed_call(:transition, id, target, [event_payload, delay])

  @doc """
  The state of the FSM in the cluster.

  See `Finitomata.state/3`.
  """
  def state(id \\ nil, target, reload? \\ :full),
    do: distributed_call(:state, id, target, reload?)
end
