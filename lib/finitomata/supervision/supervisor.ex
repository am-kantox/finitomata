defmodule Finitomata.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(id \\ nil)
  def start_link([]), do: start_link(nil)
  def start_link(id: id), do: start_link(id)
  def start_link(id), do: Supervisor.start_link(__MODULE__, id, name: fqn_name(id, Supervisor))

  @impl Supervisor
  def init(id) do
    children = [
      {Registry,
       keys: :unique, name: fqn_name(id, Registry), partitions: System.schedulers_online()},
      {Finitomata.Manager, name: fqn_name(id, Manager)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def fqn_name(id, who) do
    [Finitomata, id, who]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&inspect/1)
    |> Module.concat()
  end
end
