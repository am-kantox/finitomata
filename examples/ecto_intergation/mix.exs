defmodule EctoIntergation.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_intergation,
      version: "0.1.0",
      elixir: "~> 1.14",
      compilers: compilers(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EctoIntegration.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finitomata, path: "../.."},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"}
    ]
  end

  defp compilers(:prod), do: Mix.compilers()
  defp compilers(_), do: [:finitomata | Mix.compilers()]
end
