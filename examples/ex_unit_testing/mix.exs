defmodule ExUnitTesting.MixProject do
  use Mix.Project

  @app :ex_unit_testing
  @version "0.1.0"

  def project do
    [
      app: @app,
      name: "ExUnit Testing",
      version: @version,
      elixir: "~> 1.14",
      compilers: Mix.compilers() ++ [:finitomata],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
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
      {:mox, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: [:ci, :dev]}
    ]
  end

  defp docs do
    [
      main: "ExUnitTesting",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/#{@app}",
      # logo: "stuff/#{@app}-48x48.png",
      source_url: "https://github.com/am-kantox/#{@app}",
      # assets: "stuff/images",
      # extras: ~w[README.md stuff/fsm.md stuff/compiler.md],
      groups_for_modules: [],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@8.13.3/dist/mermaid.min.js"></script>
    <script>
    document.addEventListener("DOMContentLoaded", function () {
    mermaid.initialize({ startOnLoad: false });
    let id = 0;
    for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
      const preEl = codeEl.parentElement;
      const graphDefinition = codeEl.textContent;
      const graphEl = document.createElement("div");
      const graphId = "mermaid-graph-" + id++;
      mermaid.render(graphId, graphDefinition, function (svgSource, bindListeners) {
        graphEl.innerHTML = svgSource;
        bindListeners && bindListeners(graphEl);
        preEl.insertAdjacentElement("afterend", graphEl);
        preEl.remove();
      });
    }
    });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
