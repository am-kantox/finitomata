defmodule Finitomata.Supervisor do
  @moduledoc since: "0.26.0"
  @moduledoc """
  THe behaviour for actual _FSM_ implementations across _Finitomata_ framework.

  It ships with two predefined implementations, `Finitomata` for local
    applications and `Infinitomata` for distributed ones.
  """

  @doc "Returns whether the _FSM_ instance under `id` “branch” and with `fsm_name` name is alive"
  @callback alive?(id :: Finitomata.id(), fsm_name :: Finitomata.fsm_name()) :: boolean()
  @doc "Starts the new _FSM_ instance under `id` “branch,” the semantics is similar to `DynamicSupervisor.start_child/2`"
  @callback start_fsm(
              id :: Finitomata.id(),
              fsm_name :: Finitomata.fsm_name(),
              implementation :: Finitomata.implementation(),
              payload :: Finitomata.payload()
            ) :: DynamicSupervisor.on_start_child()
  @doc "Sends the event with an optional payload to the running _FSM_ instance to initiate a transition"
  @callback transition(
              id :: Finitomata.id(),
              fsm_name :: Finitomata.fsm_name(),
              event_payload ::
                Finitomata.Transition.event()
                | {Finitomata.Transition.event(), Finitomata.State.payload()},
              delay :: non_neg_integer()
            ) :: :ok
  @doc "Effectively initiates the `on_timer/2` callback imminently, resetting the timer"
  @callback timer_tick(id :: Finitomata.id(), fsm_name :: Finitomata.fsm_name()) :: :ok
  @doc "The `Finitomata` “branch” child specification, used from supervision trees to start supervised _FSM_ “branchs”"
  @callback child_spec(id :: Finitomata.id()) :: Supervisor.child_spec()
  @doc "Returns all the active _FSM_ instances under the `id` “branch,” it might be a heavy map"
  @callback all(Finitomata.id()) :: %{
              optional(Finitomata.fsm_name()) => %{
                optional(:node) => node(),
                optional(:reference) => reference(),
                optional(:module) => Finitomata.implementation(),
                pid: pid()
              }
            }
  @doc "Returns the state of the _FSM_ instance under `id` “branch” with `fsm_name` name"
  @callback state(
              id :: Finitomata.id(),
              fsm_name :: Finitomata.fsm_name(),
              reload? :: :cached | :payload | :full
            ) ::
              nil | Finitomata.State.t() | Finitomata.State.payload()

  use Supervisor

  @doc false
  def start_link(id \\ nil)
  def start_link([]), do: start_link(nil)
  def start_link(id: id), do: start_link(id)

  def start_link(id),
    do: Supervisor.start_link(__MODULE__, id, name: supervisor_name(id))

  @impl Supervisor
  @doc false
  def init(id) do
    children = [
      {Registry, keys: :unique, name: registry_name(id), partitions: System.schedulers_online()},
      {Finitomata.Manager, name: manager_name(id)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc false
  @spec infinitomata_name(Finitomata.id()) :: module()
  def infinitomata_name(id \\ nil), do: fq_module(id, Infinitomata, true)

  @doc false
  @spec supervisor_name(Finitomata.id()) :: module()
  def supervisor_name(id \\ nil), do: id |> fq_module(Supervisor, true) |> uninfinitomata()

  @doc false
  @spec registry_name(Finitomata.id()) :: module()
  def registry_name(id \\ nil), do: id |> fq_module(Registry, true) |> uninfinitomata()

  @doc false
  @spec manager_name(Finitomata.id()) :: module()
  def manager_name(id \\ nil), do: id |> fq_module(Manager, true) |> uninfinitomata()

  @doc false
  @spec throttler_name(Finitomata.id()) :: module()
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
