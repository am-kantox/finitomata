defmodule Finitomata.MixProject do
  use Mix.Project

  @app :finitomata
  @version "0.15.1"

  def project do
    [
      app: @app,
      name: "Finitomata",
      version: @version,
      elixir: "~> 1.12",
      compilers: compilers(Mix.env()),
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() not in [:dev, :test],
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      xref: [exclude: []],
      docs: docs(),
      # elixirc_options: [debug_info: Mix.env() in [:dev, :test, :ci]],
      releases: [],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix],
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.0"},
      {:nimble_options, "~> 0.3 or ~> 1.0"},
      {:estructura, "~> 0.5 or ~> 1.0"},
      # dev / test
      {:mox, "~> 1.0", only: [:dev, :test, :ci]},
      {:stream_data, "~> 0.5", only: [:dev, :test, :ci]},
      {:observer_cli, "~> 1.5", only: [:dev]},
      {:credo, "~> 1.0", only: [:dev, :ci]},
      {:dialyxir, "~> 1.0", only: [:dev, :ci], runtime: false},
      {:ex_doc, "~> 0.11", only: [:dev]}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer --unmatched_returns"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  defp description do
    """
    The FSM implementation generated from PlantUML textual representation.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w|stuff lib mix.exs README.md LICENSE|,
      maintainers: ["Aleksei Matiushkin"],
      licenses: ["Kantox LTD"],
      links: %{
        "GitHub" => "https://github.com/am-kantox/#{@app}",
        "Docs" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/#{@app}",
      logo: "stuff/#{@app}-48x48.png",
      source_url: "https://github.com/am-kantox/#{@app}",
      assets: "stuff/images",
      extras: ~w[README.md stuff/fsm.md stuff/compiler.md],
      groups_for_modules: [
        FSM: [Finitomata, Infinitomata, Finitomata.ExUnit],
        Internals: [
          Finitomata.Listener,
          Finitomata.Parser,
          Finitomata.State,
          Finitomata.Transition,
          Finitomata.Transition.Path
        ],
        Persistence: [
          Finitomata.Persistency,
          Finitomata.Persistency.Persistable,
          Finitomata.Persistency.Protocol
        ]
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp compilers(_), do: Mix.compilers()

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:ci), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

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
