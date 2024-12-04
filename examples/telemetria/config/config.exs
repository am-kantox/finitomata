import Config

config :finitomata, :telemetria, true

config :telemetria,
  backend: Telemetria.Backend.Telemetry,
  purge_level: :debug,
  level: :info,
  events: [
    [:tm, :f_to_c]
  ]
