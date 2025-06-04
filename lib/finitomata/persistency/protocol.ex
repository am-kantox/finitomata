defmodule Finitomata.Persistency.Protocol do
  @moduledoc """
  Default implementation of persistency adapter that does nothing but routes
    to the implementation of `Finitomata.Persistency.Persistable` for the data.
  """
  alias Finitomata.{Persistency, Persistency.Persistable}

  @behaviour Persistency

  @impl Persistency
  def load({_, _} = info) do
    Persistable.load(info)
  end

  def load(%_{} = data) do
    Persistable.load(data)
  end

  @impl Persistency
  def store(_id, %_{} = data, info) do
    Persistable.store(data, info)
  end

  def store(_id, _any, _info), do: :ok

  @impl Persistency
  def store_error(_id, %_{} = data, reason, info) do
    Persistable.store_error(data, reason, info)
  end

  def store_error(_id, _any, _reason, _info), do: :ok

  def idfy({:via, Registry, {Registry.Finitomata, name}}), do: name
  def idfy(name), do: name
end
