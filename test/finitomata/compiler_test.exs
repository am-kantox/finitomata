defmodule Finitomata.Compiler.Test do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Compile, as: Cmp

  setup tags do
    Mix.ProjectStack.post_config(Map.get(tags, :project, []))
    # Mix.Project.push(MixTest.Case.Finitomata)
    :ok
  end

  @tag project: [compilers: [:app, :finitomata, :elixir]]
  test "compiles does not require all compilers available on manifest" do
    assert Cmp.manifests() |> Enum.map(&Path.basename/1) ==
             [
               "compile.yecc",
               "compile.leex",
               "compile.erlang",
               "compile.elixir",
               "compile.finitomata"
             ]
  end

  @tag project: [compilers: [:app, :finitomata, :elixir]]
  test "unhandled" do
    module = ~s{
      defmodule TestInplace do
        @fsm """
        idle --> |ready| ready
        ready --> |do| ready
        ready --> |do| done
        """

        use Finitomata, fsm: @fsm
      end
    }

    assert "" ==
             capture_io(fn ->
               # Mix.Tasks.Compile.run(["test/seeds/compiler_test_modules.ex"])
               if Version.compare(System.version(), "1.16.0") == :lt do
                 :ok
               else
                 {[{TestInplace, _}], []} =
                   Code.with_diagnostics(fn -> Code.compile_string(module) end)
               end
             end)
  end
end
