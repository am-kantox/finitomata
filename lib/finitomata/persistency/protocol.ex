defmodule Finitomata.Persistency.Protocol do
  @moduledoc """
  Default implementation of persistency adapter that does nothing but routes
    to the implementation of `Finitomata.Persistency.Persistable` for the data.
  """
  alias Finitomata.{Persistency, Persistency.Persistable}

  @behaviour Persistency

  @impl Persistency
  def load(name, %_{} = data) do
    Persistable.load(data, name)
  end

  @impl Persistency
  def store(name, updated_data, {_, _, _, %_{} = data} = supplemental_data) do
    Persistable.store(data, name, updated_data, supplemental_data)
  end

  @impl Persistency
  def store_error(name, reason, {_, _, _, %_{} = data} = supplemental_data) do
    Persistable.store_error(data, name, reason, supplemental_data)
  end
end
