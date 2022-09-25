defmodule Finitomata.Mix.Events do
  @moduledoc false

  use Boundary, deps: [], exports: []

  use Agent

  @type diagnostics :: MapSet.t(Mix.Task.Compiler.Diagnostic.t())
  @type hooks :: MapSet.t(Finitomata.Hook.t())
  @type state :: %{hooks: hooks(), diagnostics: diagnostics()}

  def start_link,
    do:
      Agent.start_link(
        fn -> %{hooks: MapSet.new(), diagnostics: MapSet.new()} end,
        name: __MODULE__
      )

  @spec all :: state()
  def all, do: Agent.get(__MODULE__, & &1)

  @spec hooks(module()) :: hooks()
  def hooks(module),
    do:
      Agent.get(
        __MODULE__,
        &MapSet.filter(&1[:hooks], fn hook -> match?(%Finitomata.Hook{module: ^module}, hook) end)
      )

  def put(key, value) do
    Agent.update(
      __MODULE__,
      &Map.update!(&1, key, fn values -> MapSet.put(values, value) end)
    )
  end
end
