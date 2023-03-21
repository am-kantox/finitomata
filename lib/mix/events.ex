defmodule Finitomata.Mix.Events do
  @moduledoc false

  use Agent

  @type diagnostics :: MapSet.t(Mix.Task.Compiler.Diagnostic.t())
  @type hooks :: MapSet.t(Finitomata.Hook.t())
  @type state :: %{hooks: hooks(), declarations: hooks(), diagnostics: diagnostics()}

  def start_link,
    do:
      Agent.start_link(
        fn -> %{hooks: MapSet.new(), declarations: MapSet.new(), diagnostics: MapSet.new()} end,
        name: __MODULE__
      )

  @spec all :: state()
  def all, do: Agent.get(__MODULE__, & &1)

  @spec hooks(module()) :: hooks()
  def hooks(module),
    do:
      Agent.get(
        __MODULE__,
        fn all ->
          all[:hooks]
          |> Enum.filter(&match?(%{__struct__: Finitomata.Hook, module: ^module}, &1))
          |> MapSet.new()
        end
      )

  @spec declaration(module()) :: Finitomata.Hook.t() | nil
  def declaration(module),
    do:
      Agent.get(
        __MODULE__,
        &Enum.find(&1[:declarations], fn hook ->
          match?(%{__struct__: Finitomata.Hook, module: ^module}, hook)
        end)
      )

  def put(key, value) do
    Agent.update(
      __MODULE__,
      &Map.update!(&1, key, fn values -> MapSet.put(values, value) end)
    )
  end
end
