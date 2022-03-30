defmodule Finitomata.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(state \\ []),
    do: Supervisor.start_link(__MODULE__, state)

  @impl Supervisor
  def init(_) do
    children = [
      {Registry,
       keys: :unique, name: Registry.Finitomata, partitions: System.schedulers_online()},
      Finitomata.Manager
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
