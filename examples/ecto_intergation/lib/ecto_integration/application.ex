defmodule EctoIntegration.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [EctoIntegration.Repo]

    opts = [strategy: :one_for_one, name: EctoIntegration.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
