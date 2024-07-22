import Config

config :logger, :default_handler, level: :debug
config :logger, :default_formatter, colors: [info: :magenta]

if Mix.env() in [:test, :dev] do
  config :finitomata, :ext_behaviour, Finitomata.Test.WithMocks.ExtBehaviour.Mox
end
