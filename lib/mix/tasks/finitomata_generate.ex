defmodule Mix.Tasks.Finitomata.Generate do
  @shortdoc "Generates the FSM scaffold for the `Finitomata` instance"

  @moduledoc """
  Mix task to generate the `Finitomata` instance scaffold.

  By running `mix finitomata.generate --module MyFSM` one would be prompted
  to enter the _FSM_ declartion if `ELIXIR_EDITOR` environment variable is set,
  in the same way as `IEx.Helpers.open/0` does. THen the scaffold implementation
  (and optionally the test for it) will be generated.

  ### Allowed arguments

  - **`--module: :string`** __[mandatory]__ the name of the module to generate, it will be prepended
    with `OtpApp.Finitomata.`
  - **`--fsm-file: :string`** __[optional, default: `nil`]__ the name of the file to read the FSM description from,
    the `ELIXIR_EDITOR` will be opened to enter a description otherwise
  - **`--syntax: :string`** __[optional, default: `:flowchart`]__ the syntax to be used, might be
    `:flowchart`, `:state_diagram`, or a module name for custom implementation
  - **`--timer: :integer`** __[optional, default: `false`]__ whether to use recurrent calls in
    this _FSM_ implementation
  - **`--auto-terminate: :boolean`** __[optional, default: `false`]__ whether the ending states should
    lead to auto-termination
  - **`--listener: :string`** __[optional, default: `nil`]__ the listener implementation
  - **`--impl-for: :string`** __[optional, default: `:all`]__ what callbacks should be auto-implemented 
  - **`--generate-test: :boolean`** __[optional, default `false`]__ whether the test should be
    generated as well
  - **`--callback: :string`** __[optional, default: `nil`]__ the function to be called before actual generation

  ### Example

  ```sh
  mix finitomata.generate --module MyFSM --timer 1000 --auto-terminate true --generate-test true
  ```
  """

  use Mix.Task

  @finitomata_default_path "lib/finitomata"
  @stub "idle --> |start| started\nstarted --> |run| running\nrunning --> |stop| stopped"

  @impl Mix.Task
  @doc false
  def run(args) do
    Mix.Task.run("compile")
    Finitomata.Mix.load_app()

    {opts, _pass_thru, []} =
      OptionParser.parse(args,
        strict: [
          module: :string,
          prefix: :string,
          fsm_file: :string,
          syntax: :string,
          timer: :integer,
          auto_terminate: :string,
          listener: :string,
          impl_for: :string,
          generate_test: :boolean,
          callback: :string
        ]
      )

    module = Keyword.fetch!(opts, :module)

    callback =
      case Keyword.fetch(opts, :callback) do
        {:ok, fun} ->
          fun
          |> String.split(~w[& . /], trim: true)
          |> Enum.reverse()
          |> then(fn [a, f | m] ->
            m
            |> Enum.reverse()
            |> Module.concat()
            |> Function.capture(
              String.to_existing_atom(f),
              String.to_integer(a)
            )
          end)

        _ ->
          nil
      end

    prefix =
      Keyword.get_lazy(opts, :prefix, fn ->
        Mix.ProjectStack
        |> GenServer.whereis()
        |> case do
          nil ->
            [Finitomata.Implementations]

          pid when is_pid(pid) ->
            Mix.Project.get()
            |> Module.split()
            |> List.first()
            |> List.wrap()
            |> Kernel.++(["Finitomata"])
        end
      end)

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
        {:ok, value} when is_integer(value) and value > 0 ->
          "timer: #{value}"

        {:ok, value} ->
          value
          |> Integer.parse()
          |> then(fn
            {i, _} when is_integer(i) and i > 0 -> "timer: #{i}"
            :error -> "timer: true"
          end)

        :error ->
          nil
      end

    auto_terminate_clause =
      opts
      |> Keyword.fetch(:auto_terminate)
      |> case do
        :error -> nil
        {:ok, value} when is_boolean(value) -> "auto_terminate: #{value}"
        {:ok, value} -> "auto_terminate: " <> parse_auto_terminate(value)
      end

    {to_implement, impl_for_clause} =
      opts
      |> Keyword.fetch(:impl_for)
      |> case do
        :error -> {[], nil}
        {:ok, value} -> parse_impl_for(value)
      end

    test? = Keyword.get(opts, :generate_test, false)

    listener_clause =
      opts
      |> Keyword.fetch(:listener)
      |> case do
        :error ->
          if test?, do: "listener: :mox", else: nil

        {:ok, "mox"} ->
          "listener: :mox"

        {:ok, ":mox"} ->
          "listener: :mox"

        {:ok, value} ->
          if test?,
            do: "listener: {:mox, " <> inspect(value) <> "}",
            else: "listener: " <> inspect(value)
      end

    use_clause =
      [
        "use Finitomata",
        "fsm: @fsm",
        syntax_clause,
        timer_clause,
        auto_terminate_clause,
        listener_clause,
        impl_for_clause
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

    module = Module.concat(prefix ++ [module])

    fsm =
      case {Keyword.fetch(opts, :fsm_file), System.fetch_env("ELIXIR_EDITOR")} do
        {{:ok, file}, _} ->
          case File.read(file) do
            {:ok, fsm_definition} ->
              fsm_definition

            error ->
              Mix.shell().info([
                [:bright, :red, "✗ #{file}", :reset],
                " file could not be read (error: #{inspect(error)}). ",
                [:yellow, "Stub FSM definition", :reset],
                " will be generated."
              ])

              @stub
          end

        {_, :error} ->
          Mix.shell().info([
            [:bright, :red, "✗ #{ELIXIR_EDITOR}", :reset],
            " environment variable is not set. ",
            [:yellow, "Stub FSM definition", :reset],
            " will be generated."
          ])

          @stub

        {_, {:ok, editor}} ->
          open_in_editor(@stub, editor)
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
          auto_terminate?: not is_nil(auto_terminate_clause),
          to_implement: to_implement
        )

        File.write!(target_file, Code.format_file!(target_file))

        case callback do
          fun when is_function(fun, 1) -> fun.(module)
          fun when is_function(fun, 2) -> fun.(module, target_file)
          _ -> :ok
        end

        Mix.shell().info([
          [:bright, :blue, "* #{inspect(module)}", :reset],
          " has been created."
        ])

        if test? do
          :ok = Mix.Task.reenable("compile")

          with {:noop, []} <- Mix.Task.run("compile", [target_file]) do
            {output, _} = System.cmd("mix", ["compile", target_file])
            IO.puts(output)
          end

          Mix.Task.run("finitomata.generate.test", ["--module", inspect(module)])
        end

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

  # gracefully stolen from https://github.com/fuelen/owl/blob/v0.11.0/lib/owl/io.ex#L230
  defp open_in_editor(data, elixir_editor) do
    dir = System.tmp_dir!()

    random_name =
      9
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64()
      |> binary_part(0, 9)

    filename = "fini-#{random_name}"
    tmp_file = Path.join(dir, filename)
    File.write!(tmp_file, data)

    elixir_editor =
      if String.contains?(elixir_editor, "__FILE__") do
        String.replace(elixir_editor, "__FILE__", tmp_file)
      else
        elixir_editor <> " " <> tmp_file
      end

    {_, 0} = System.shell(elixir_editor)
    File.read!(tmp_file)
  end

  @doc false
  defp parse_auto_terminate("true"), do: "true"

  defp parse_auto_terminate(specified) do
    specified
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(~r/[,:]+/)
    |> Enum.map(&String.to_atom/1)
    |> inspect()
  end

  @doc false
  defp parse_impl_for(specified) do
    impls = ~w|on_enter on_exit on_failure on_fork on_start on_terminate|a

    states =
      specified
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.split(~r/[,:]+/)
      |> Enum.map(&String.to_atom/1)

    to_implement =
      case states do
        [:all] -> []
        [:none] -> impls
        list when is_list(list) -> impls -- list
      end

    result =
      case states do
        [:all] -> :all
        [:none] -> :none
        [transition] when is_atom(transition) -> transition
        list when is_list(list) -> list
      end
      |> inspect()

    {to_implement, "impl_for: " <> result}
  end
end
