import Config

config :ecto_intergation,
  ecto_repos: [EctoIntegration.Repo]

config :ecto_intergation, EctoIntegration.Repo,
  database: "ecto_intergation_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
