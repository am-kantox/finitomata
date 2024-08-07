import Config

config :logger, :default_handler, level: :info
config :logger, :default_formatter, colors: [info: :magenta]

config :finitomata, :mox_envs, [:test, :finitomata]

if Mix.env() in [:test, :dev, :finitomata] do
  config :finitomata, :ext_behaviour, Finitomata.Test.WithMocks.ExtBehaviour.Mox
end
