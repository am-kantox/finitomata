defmodule Finitomata.Application do
  @moduledoc false

  use Application

  @impl true
  @doc false
  def start(_type \\ :normal, _args \\ []) do
    children =
      case Application.get_env(:finitomata, :start_as) do
        Finitomata ->
          [Finitomata]

        {Finitomata, name} when is_atom(name) ->
          [{Finitomata, name}]

        distributed when distributed in [Infinitomata, :distributed] ->
          [Infinitomata]

        {distributed, name} when is_atom(name) and distributed in [Infinitomata, :distributed] ->
          [{Infinitomata, name}]

        nil ->
          []

        _ ->
          raise ArgumentError,
                "`:start_as` key is expected to be `{Finitomata, name}` or `{Infinitomata, name}`"
      end

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
