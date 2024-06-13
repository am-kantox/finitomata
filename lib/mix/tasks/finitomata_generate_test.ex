defmodule Mix.Tasks.Finitomata.Generate.Test do
  @shortdoc "Generates the test scaffold for the `Finitomata` instance"
  @moduledoc """
  Mix task to generate the `Finitomata.ExUnit` test scaffold.
  """

  use Mix.Task

  @finitomata_tests_path "test/finitomata"

  @impl Mix.Task
  @doc false
  def run(args) do
    Mix.Task.run("compile")
    Finitomata.Mix.load_app()

    {opts, _pass_thru, []} =
      OptionParser.parse(args, strict: [module: :string, file: :string, dir: :string])

    module = Keyword.fetch!(opts, :module)

    test_dir = Keyword.get(opts, :dir, @finitomata_tests_path)
    module = Module.concat([module])

    test_file =
      Keyword.get(
        opts,
        :file,
        module |> Module.split() |> List.last() |> Macro.underscore() |> Kernel.<>("_test.exs")
      )

    if module?(module) do
      paths =
        module.fsm()
        |> Finitomata.Transition.paths()
        |> Enum.map(&{&1, transform_path(module.__config__(:auto_terminate), &1)})

      test_module = Module.concat([module, "Test"])
      target_file = Path.join(test_dir, test_file)

      Mix.Generator.copy_template(
        Path.expand("test_template.eex", __DIR__),
        target_file,
        module: module,
        test_module: test_module,
        paths: paths
      )

      File.write!(target_file, Code.format_file!(target_file))

      Mix.shell().info([
        [:bright, :blue, "* #{inspect(test_module)}", :reset],
        " has been created for ",
        [:blue, inspect(module), :reset],
        ", do not forget to:\n",
        "  ▹ amend assertions to fit your business logic\n",
        "  ▹ add `listener: :mox` (or actual listener) to `Finitomata` declaration"
      ])
    end
  end

  @doc false
  defp transform_path(auto_terminate?, %Finitomata.Transition.Path{path: path}),
    do: transform_path(auto_terminate?, path)

  defp transform_path(auto_terminate?, path) do
    path
    |> Enum.reduce([], fn
      {event, state}, [] ->
        [[{event, state}]]

      {event, state}, [curr | rest] ->
        if event |> to_string() |> String.ends_with?("!"),
          do: [curr ++ [{event, state}] | rest],
          else: [[{event, state}], curr | rest]
    end)
    |> then(&maybe_join_ending(auto_terminate?, &1))
    |> Enum.reverse()
  end

  defp maybe_join_ending(false, path), do: path
  defp maybe_join_ending(true, [[{:__end__, :*}] = last, prev | rest]), do: [prev ++ last | rest]

  defp module?(module) do
    with {:module, ^module} <- Code.ensure_compiled(module),
         true <- function_exported?(module, :fsm, 0) do
      true
    else
      _ ->
        Mix.shell().error([
          :yellow,
          "* #{inspect(module)}",
          :reset,
          " is not found or is not a `Finitomata` instance"
        ])

        false
    end
  end
end
