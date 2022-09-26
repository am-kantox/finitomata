defmodule Mix.Tasks.Compile.Finitomata do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  @moduledoc false

  use Boundary, deps: [Finitomata]

  use Mix.Task.Compiler

  alias Mix.Task.Compiler
  alias Finitomata.{Hook, Mix.Events, Transition}

  @preferred_cli_env :dev
  @manifest_events "finitomata_events"

  @impl Compiler
  def run(argv) do
    Events.start_link()

    Compiler.after_compiler(:app, &after_compiler(&1, argv))

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  @impl Compiler
  def manifests, do: [manifest_path(@manifest_events)]

  @doc false
  @impl Compiler
  def clean, do: :ok

  @doc false
  def trace({remote, meta, Finitomata, :__using__, 1}, env)
      when remote in ~w|remote_macro imported_macro|a do
    Events.put(
      :declarations,
      struct(Finitomata.Hook,
        env: env,
        module: env.module,
        kind: :defmacro,
        fun: :__using__,
        arity: 1,
        args: meta
      )
    )

    :ok
  end

  def trace({:remote_macro, _meta, Finitomata.Hook, :__before_compile__, 1}, %Macro.Env{
        module: module
      }) do
    module
    |> Events.hooks()
    |> to_diagnostics(module |> Module.get_attribute(:__config__) |> Map.get(:fsm))
    |> add_diagnostics()
    |> amend_using_info(module)
  end

  def trace(_event, _env), do: :ok

  @spec after_compiler({status, [Mix.Task.Compiler.Diagnostic.t()]}, any()) ::
          {status, [Mix.Task.Compiler.Diagnostic.t()]}
        when status: Mix.Task.Compiler.status()
  defp after_compiler({status, diagnostics}, _argv) do
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)

    %{diagnostics: finitomata_diagnostics} = Events.all()

    {finitomata_status, _full, _added, _removed} = manifest(finitomata_diagnostics)

    status =
      case {status, finitomata_status} do
        {:error, _} -> :error
        {:noop, status} -> status
        {:ok, _} -> :ok
      end

    {status, diagnostics ++ MapSet.to_list(finitomata_diagnostics)}
  end

  @spec diagnostic(message :: binary(), opts :: keyword()) :: Mix.Task.Compiler.Diagnostic.t()
  defp diagnostic(message, opts) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "finitomata",
      details: nil,
      file: "unknown",
      message: message,
      position: nil,
      severity: :information
    }
    |> Map.merge(Map.new(opts))
  end

  @type ambiguous ::
          {Finitomata.Transition.state(),
           {Finitomata.Transition.event(), [Finitomata.Transition.state()]}}
  @type disambiguated ::
          {Finitomata.Transition.state(),
           {Finitomata.Transition.event(), [Finitomata.Transition.state()], Hook.t()}}
  @type diagnostics :: %{
          explicit: [disambiguated()],
          partial: [disambiguated()],
          implicit: [disambiguated()],
          unhandled: [ambiguous()]
        }

  @spec to_diagnostics(Events.hooks(), [Transition.t()]) :: diagnostics()
  defp to_diagnostics(hooks, fsm) do
    declared = Enum.group_by(hooks, &hd(&1.args))
    initial = %{explicit: [], partial: [], implicit: [], unhandled: []}

    fsm
    |> Transition.ambiguous()
    |> Enum.reduce(initial, fn {from, {event, tos}}, acc ->
      declared
      |> Map.get(from, [])
      |> add_diagnostic({from, {event, tos}}, acc)
    end)
  end

  @spec add_diagnostic([Hook.t()], ambiguous(), diagnostics()) :: diagnostics()
  defp add_diagnostic([], {from, {event, tos}}, diagnostics),
    do: %{diagnostics | unhandled: [{from, {event, tos}} | diagnostics.unhandled]}

  defp add_diagnostic(hooks, {from, {event, tos}}, diagnostics) do
    Enum.reduce(hooks, diagnostics, fn
      %Hook{args: [^from, ^event, _, _]} = hook, acc ->
        %{acc | explicit: [{from, {event, tos, hook}} | acc.explicit]}

      # [AM] check guards
      # %Hook{args: [from, {event, _, _}, _, _], guards: _} = hook, acc when is_atom(event) ->
      #   %{acc | implicit: [hook | acc.implicit]}

      %Hook{args: [^from, {event, _, _}, _, _]} = hook, acc when is_atom(event) ->
        %{acc | implicit: [{from, {event, tos, hook}} | acc.implicit]}
    end)
  end

  @spec add_diagnostics(diagnostics()) :: diagnostics()
  defp add_diagnostics(%{explicit: _, partial: _, implicit: _} = hooks) do
    hooks
    |> Map.take(~w|explicit partial implicit|a)
    |> Enum.each(fn {type, hooks} ->
      Enum.each(hooks, fn
        {_from, {_event, _tos, %Hook{} = hook}} = info ->
          Events.put(
            :diagnostics,
            type
            |> disambiguated_message(info)
            |> diagnostic(
              severity: disambiguated_security(type),
              details: Hook.details(hook),
              position: hook.env.line,
              file: hook.env.file
            )
          )
      end)
    end)

    hooks
  end

  @spec disambiguated_security(:explicit | :partial | :implicit) :: :hint | :info
  def disambiguated_security(:explicit), do: :hint
  def disambiguated_security(:partial), do: :hint
  def disambiguated_security(:implicit), do: :information

  @spec disambiguated_message(:explicit | :partial | :implicit, disambiguated()) :: String.t()
  defp disambiguated_message(:explicit, {from, {event, tos, %Hook{} = _hook}}) do
    "Ambiguous transition " <>
      inspect(%Transition{from: from, to: tos, event: event}) <>
      " seems to be explicitly handled.\n" <>
      "Make sure all possible target states are reachable!"
  end

  defp disambiguated_message(:implicit, {from, {event, tos, %Hook{} = _hook}}) do
    "Ambiguous transition " <>
      inspect(%Transition{from: from, to: tos, event: event}) <>
      " seems to be implicitly handled.\n" <>
      "Make sure all possible target states are reachable!"
  end

  @spec amend_using_info(diagnostics(), module()) :: :ok
  defp amend_using_info(%{unhandled: []}, _module), do: :ok

  defp amend_using_info(%{unhandled: unhandled}, module) do
    module
    |> Events.declaration()
    |> case do
      %Hook{} = hook ->
        pos = if Keyword.keyword?(hook.args), do: Keyword.get(hook.args, :line, hook.env.line)

        message =
          [
            "This FSM declaration contains ambiguous transitions which are not handled:"
            | Enum.map(unhandled, fn {from, {event, tos}} ->
                "    " <>
                  inspect(%Transition{from: from, to: tos, event: event}) <>
                  " must be handled"
              end)
          ]
          |> Enum.join("\n")

        Events.put(
          :diagnostics,
          diagnostic(message,
            severity: :warning,
            details: Hook.details(hook),
            position: pos,
            file: hook.env.file
          )
        )

      nil ->
        Mix.shell().info([
          [:bright, :yellow, "warning: ", :reset],
          "inconsistent FSM data collected from ",
          [:bright, :blue, inspect(module), :reset]
        ])
    end
  end

  @doc experimental: true, todo: true
  @spec manifest(MapSet.t(Hook.t())) ::
          {Mix.Task.Compiler.status(), MapSet.t(Hook.t()), MapSet.t(Hook.t()), MapSet.t(Hook.t())}
  defp manifest(diagnostics) do
    {full, added, removed} =
      @manifest_events
      |> read_manifest()
      |> case do
        nil ->
          {diagnostics, diagnostics, []}

        old ->
          old_by_module = Enum.group_by(old, & &1.file)
          diagnostics_by_module = Enum.group_by(diagnostics, & &1.file)

          full =
            old_by_module
            |> Map.merge(diagnostics_by_module)
            |> Map.values()
            |> List.flatten()
            |> MapSet.new()

          old =
            old_by_module
            |> Map.take(Map.keys(diagnostics_by_module))
            |> Map.values()
            |> List.flatten()
            |> MapSet.new()

          {full, MapSet.difference(diagnostics, old), MapSet.difference(old, diagnostics)}
      end

    write_manifest(@manifest_events, full)

    status =
      [added, removed]
      |> Enum.map(fn diagnostics ->
        diagnostics
        |> Enum.filter(&match?(%Mix.Task.Compiler.Diagnostic{severity: :warning}, &1))
        |> Enum.map(fn %Mix.Task.Compiler.Diagnostic{} = diagnostic ->
          loc = Enum.join([Path.relative_to_cwd(diagnostic.file), diagnostic.position], ":")
          {diagnostic.message, loc}
        end)
      end)
      |> case do
        [[], []] -> :noop
        [_added, _removed] -> :ok
      end

    full
    |> Enum.filter(&match?(%Mix.Task.Compiler.Diagnostic{severity: :warning}, &1))
    |> Enum.each(fn %Mix.Task.Compiler.Diagnostic{} = diagnostic ->
      loc = Enum.join([Path.relative_to_cwd(diagnostic.file), diagnostic.position], ":")

      Mix.shell().info([
        [:bright, :yellow, "warning: ", :reset],
        diagnostic.message,
        "\n  ",
        loc
      ])
    end)

    {status, full, added, removed}
  end

  @spec manifest_path(binary()) :: binary()
  defp manifest_path(name),
    do: Mix.Project.config() |> Mix.Project.manifest_path() |> Path.join("compile.#{name}")

  @spec read_manifest(binary()) :: term()
  defp read_manifest(name) do
    unless Mix.Utils.stale?([Mix.Project.config_mtime()], [manifest_path(name)]) do
      name
      |> manifest_path()
      |> File.read()
      |> case do
        {:ok, manifest} -> :erlang.binary_to_term(manifest)
        _ -> nil
      end
    end
  end

  @spec write_manifest(binary(), term()) :: :ok
  defp write_manifest(name, data) do
    path = manifest_path(name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(data))
  end
end
