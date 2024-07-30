defmodule Mix.Tasks.Finitomata.Generate do
  @shortdoc "Generates the FSM scaffold for the `Finitomata` instance"
  @moduledoc """
  Mix task to generate the `Finitomata` instance scaffold.
  """

  use Mix.Task

  @finitomata_default_path "lib/finitomata"

  @impl Mix.Task
  @doc false
  def run(args) do
    Mix.Task.run("compile")
    Finitomata.Mix.load_app()

    {opts, _pass_thru, []} =
      OptionParser.parse(args,
        strict: [
          module: :string,
          syntax: :string,
          timer: :integer,
          auto_terminate: :string,
          listener: :string
        ]
      )

    module = Keyword.fetch!(opts, :module)

    {syntax, syntax_name} =
      opts
      |> Keyword.fetch(:syntax)
      |> case do
        :error -> {Finitomata.Mermaid, :flowchart}
        {:ok, :flowchart} -> {Finitomata.Mermaid, :flowchart}
        {:ok, :state_diagram} -> {Finitomata.PlantUML, :state_diagram}
        {:ok, other} -> [other] |> Module.concat() |> then(&{&1, &1})
      end

    syntax_clause = "syntax: " <> inspect(syntax_name)

    timer_clause =
      opts
      |> Keyword.fetch(:timer)
      |> case do
        :error ->
          nil

        {:ok, value} ->
          value
          |> Integer.parse()
          |> then(fn
            {i, _} when is_integer(i) and i > 0 -> "timer: #{i}"
            :error -> "timer: true"
          end)
      end

    auto_terminate_clause =
      opts
      |> Keyword.fetch(:auto_terminate)
      |> case do
        :error -> nil
        {:ok, value} -> "auto_terminate: " <> parse_true_or_atom_or_list(value)
      end

    listener_clause =
      opts
      |> Keyword.fetch(:listener)
      |> case do
        :error -> nil
        {:ok, value} -> "listener: " <> inspect(value)
      end

    use_clause =
      [
        "use Finitomata",
        "fsm: @fsm",
        syntax_clause,
        timer_clause,
        auto_terminate_clause,
        listener_clause
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    dir = @finitomata_default_path

    file =
      [module]
      |> Module.concat()
      |> Module.split()
      |> Enum.map_join("_", &Macro.underscore/1)
      |> Kernel.<>(".ex")

    target_file = Path.join(dir, file)

    otp_app =
      Mix.ProjectStack
      |> GenServer.whereis()
      |> case do
        nil ->
          []

        pid when is_pid(pid) ->
          Mix.Project.get()
          |> Module.split()
          |> List.first()
          |> List.wrap()
          |> Kernel.++(["Finitomata"])
      end

    module = Module.concat(otp_app ++ [module])

    fsm =
      case System.fetch_env("ELIXIR_EDITOR") do
        :error ->
          Mix.shell().info([
            [:bright, :red, "✗ #{ELIXIR_EDITOR}", :reset],
            " environment variable is not set. ",
            [:yellow, "Stub FSM definition", :reset],
            " will be generated."
          ])

          "idle --> |start| started\nstarted --> |run| running\nrunning --> |stop| stopped"

        _ ->
          Owl.IO.open_in_editor("idle --> |start| started\n")
      end

    case syntax.parse(fsm) do
      {:ok, transitions} ->
        Mix.Generator.copy_template(
          Path.expand("fsm_template.eex", __DIR__),
          target_file,
          module: module,
          fsm: fsm,
          transitions: transitions,
          use_clause: use_clause,
          timer?: not is_nil(timer_clause),
          auto_terminate?: not is_nil(auto_terminate_clause)
        )

        File.write!(target_file, Code.format_file!(target_file))

        Mix.shell().info([
          [:bright, :blue, "* #{inspect(module)}", :reset],
          " has been created."
        ])

      {:error, message, _, _, {line, col}, pos} ->
        Mix.shell().info([
          [:bright, :red, "✗ Invalid FSM declaration", :reset],
          "\n\n",
          fsm,
          "\n\n",
          "Error: ",
          [:yellow, message, :reset],
          "\nLine: ",
          [:yellow, line, :reset],
          ", Column: ",
          [:yellow, col, :reset],
          ", Position: ",
          [:yellow, pos, :reset]
        ])
    end
  end

  @doc false
  defp parse_true_or_atom_or_list(true), do: "true"
  defp parse_true_or_atom_or_list("true"), do: "true"

  defp parse_true_or_atom_or_list(specified) do
    inner =
      specified
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.split(~r/[,:]+/)
      |> Enum.map_join(", ", &(":" <> &1))

    "[" <> inner <> "]"
  end
end
