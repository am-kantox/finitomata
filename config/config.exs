import Config

config :logger, level: :error
config :logger, :default_handler, level: :error
config :logger, compile_time_purge_matching: [[level_lower_than: :error]]
