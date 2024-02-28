defmodule ExUnitTesting.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_unit_testing,
      version: "0.1.0",
      elixir: "~> 1.16",
      compilers: [:finitomata | Mix.compilers()],
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
      {:finitomata, path: "../../../finitomata"},
      {:mox, "~> 1.0"}
    ]
  end
end
