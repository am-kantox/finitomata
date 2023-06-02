defmodule EctoIntegration.Repo do
  use Ecto.Repo,
    otp_app: :ecto_integration,
    adapter: Ecto.Adapters.Postgres
end
