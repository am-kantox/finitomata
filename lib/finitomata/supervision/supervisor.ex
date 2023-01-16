defmodule Finitomata.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(id \\ nil)
  def start_link([]), do: start_link(nil)
  def start_link(id: id), do: start_link(id)

  def start_link(id),
    do: Supervisor.start_link(__MODULE__, id, name: fq_module(id, Supervisor, true))

  @impl Supervisor
  def init(id) do
    children = [
      {Registry,
       keys: :unique, name: fq_module(id, Registry, true), partitions: System.schedulers_online()},
      {Finitomata.Manager, name: fq_module(id, Manager, true)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @spec fq_module(id :: any(), who :: any(), atomize? :: boolean()) :: module() | [any()]
  def fq_module(id, who, atomize? \\ false)
  def fq_module(id, who, false), do: [Finitomata, id, who]

  def fq_module(id, who, true) do
    id
    |> fq_module(who, false)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&inspect/1)
    |> Module.concat()
  end
end
