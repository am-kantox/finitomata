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
config :logger, compile_time_purge_matching: [[level_lower_than: level]]
