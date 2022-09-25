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
    pos = if Keyword.keyword?(meta), do: Keyword.get(meta, :line, env.line)
    message = "This file contains Finitomata implementation"

    Events.put(
      :diagnostics,
      diagnostic(message, severity: :hint, details: env.context, position: pos, file: env.file)
    )

    :ok
  end

  def trace({:remote_macro, _meta, Finitomata.Hook, :__before_compile__, 1}, %Macro.Env{
        module: module
      }) do
    module
    |> Events.hooks()
    |> to_diagnostics(module |> Module.get_attribute(:__config__) |> Map.get(:fsm))
    |> amend_using_info()
  end

  def trace(_event, _env), do: :ok

  @spec after_compiler({status, [Mix.Task.Compiler.Diagnostic.t()]}, any()) ::
          {status, [Mix.Task.Compiler.Diagnostic.t()]}
        when status: atom()
  defp after_compiler({status, diagnostics}, _argv) do
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)

    %{hooks: hooks, diagnostics: finitomata_diagnostics} = Events.all()

    {_full, _added, _removed} = manifest(hooks)
    IO.inspect(finitomata_diagnostics)
    IO.inspect({status, diagnostics})
    IO.inspect(hooks)

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

  @spec hook(Hook.t()) :: module()
  defp hook(%Hook{module: module}), do: module

  @spec to_diagnostics(Events.hooks(), [Transition.t()]) :: Events.diagnostics()
  defp to_diagnostics(hooks, fsm) do
    declared = Enum.group_by(hooks, &hd(&1.args))

    IO.inspect({declared, Transition.ambiguous(fsm)}, label: "HOOKS")

    fsm
    |> Transition.ambiguous()
    |> Enum.reduce([], fn {from, {event, tos}}, acc ->
      declared
      |> Map.get(from, [])
      |> Enum.filter(&match?(%Hook{args: [^from, ^event, _, _]}, &1))
      |> case do
        [] ->
          [{from, {event, tos}} | acc]

        some ->
          Enum.each(some, fn
            %Hook{} = hook ->
              message =
                "Ambiguous transition ‹#{from} -- <#{event}> --> #{inspect(tos)}› seems to be handled.\n" <>
                  "Make sure all possible targte states are reachable!"

              Events.put(
                :diagnostics,
                diagnostic(message,
                  severity: :hint,
                  details: Hook.details(hook),
                  position: hook.env.line,
                  file: hook.env.file
                )
              )
          end)

          acc
      end
    end)
  end

  @spec amend_using_info([
          {Finitomata.Transition.state(),
           {Finitomata.Transition.event(), [Finitomata.Transition.state()]}}
        ]) :: :ok
  defp amend_using_info([]), do: :ok
  defp amend_using_info(unhandled), do: IO.puts(inspect(unhandled, label: "UNHANDLED"))

  @doc experimental: true, todo: true
  @spec manifest(MapSet.t(Hook.t())) ::
          {MapSet.t(Hook.t()), MapSet.t(Hook.t()), MapSet.t(Hook.t())}
  defp manifest(hooks) do
    hooks = hooks |> Enum.map(&hook/1) |> Enum.frequencies()

    {full, added, removed} =
      @manifest_events
      |> read_manifest()
      |> IO.inspect(label: "MANIFEST")
      |> case do
        nil ->
          {hooks, hooks, %{}}

        old ->
          {maybe_changed_new, added} = Map.split(hooks, Map.keys(old))
          {maybe_changed_old, preserved} = Map.split(old, Map.keys(hooks))

          {
            maybe_changed_old
            |> Map.merge(maybe_changed_new)
            |> Map.merge(preserved)
            |> Map.merge(added),
            added,
            preserved
          }
      end

    write_manifest(@manifest_events, full)

    [added: added, removed: removed]
    |> Enum.map(fn {k, v} -> {k, Enum.map(v, &inspect(&1, limit: :infinity))} end)
    |> case do
      events ->
        Mix.shell().info("Finitomata events: " <> inspect(events))
    end

    {full, added, removed}
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
