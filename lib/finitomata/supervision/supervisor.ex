defmodule Finitomata.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl Supervisor
  def init(_) do
    children = [
      {Registry, keys: :unique, name: Registry.Finitomata},
      Finitomata.Manager
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
