defmodule FinitomataWithTelemetria.MixProject do
  use Mix.Project

  def project do
    [
      app: :finitomata_with_telemetria,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      compilers: [:finitomata, :telemetria | Mix.compilers()],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {FinitomataWithTelemetria.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finitomata, path: "../../"},
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetria, "~> 0.22"}
    ]
  end
end
