import Config

config :ecto_integration,
  ecto_repos: [EctoIntegration.Repo]

config :ecto_integration, EctoIntegration.Repo,
  database: "ecto_integration_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
