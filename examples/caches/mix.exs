defmodule Caches.MixProject do
  use Mix.Project

  def project do
    [
      app: :caches,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cachex, "~> 3.6"},
      {:con_cache, "~> 1.0"},
      {:finitomata, path: "../../../finitomata/"},
      {:benchee, "~> 1.1"}
    ]
  end
end
