defmodule Finitomata.Persistency.Protocol do
  @moduledoc """
  Default implementation of persistency adapter that does nothing but routes
    to the implementation of `Finitomata.Persistency.Persistable` for the data.
  """
  alias Finitomata.{Persistency, Persistency.Persistable}

  @behaviour Persistency

  @impl Persistency
  def load(data, opts \\ []), do: Persistable.load(data, opts)

  @impl Persistency
  def store(_id, data, info) do
    Persistable.store(data, info)
  rescue
    Protocol.UndefinedError -> :ok
  end

  @impl Persistency
  def store_error(_id, data, reason, info) do
    Persistable.store_error(data, reason, info)
  rescue
    Protocol.UndefinedError -> :ok
  end

  def idfy({:via, Registry, {_, name}}), do: name
  def idfy(name), do: name
end
