import Config

level =
  case Mix.env() do
    :test -> :debug
    :finitomata -> :debug
    :prod -> :warning
    :dev -> :error
  end

config :logger, level: level
config :logger, :default_handler, level: level
config :logger, :default_formatter, colors: [info: :magenta]
config :logger, compile_time_purge_matching: [[level_lower_than: level]]

config :finitomata, :mox_envs, [:test, :finitomata]

if Mix.env() in [:test, :dev, :finitomata] do
  config :finitomata, :ext_behaviour, Finitomata.Test.WithMocks.ExtBehaviour.Mox
end
