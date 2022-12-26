defmodule EctoIntegration.Repo do
  use Ecto.Repo,
    otp_app: :ecto_intergation,
    adapter: Ecto.Adapters.Postgres
end
