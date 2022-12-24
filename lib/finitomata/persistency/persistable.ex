defprotocol Finitomata.Persistency.Persistable do
  @moduledoc """
  The protocol to be implemented for custom data to be used in pair with
    `Finitomata.Persistency.Protocol` persistency adapter.

  For that combination, one should implement the protocol for that particular
    struct _and_ specify `Finitomata.Persistency.Protocol` as a `persistency`
    in a call to `use Finitomata`.

  ```elixir
  use Finitomata, …, persistency: Finitomata.Persistency.Protocol
  ```
  """

  @fallback_to_any false

  @doc "Loads the entity from some external storage"
  def load(data, name)

  @doc "Persists the transitioned entity to some external storage"
  def store(data, name, updated_data, supplemental_data)

  @doc "Persists the error happened while an attempt to transition the entity"
  def store_error(data, name, reason, supplemental_data)
end

defimpl Finitomata.Persistency.Persistable,
  for: [
    Any,
    Atom,
    BitString,
    Float,
    Function,
    Integer,
    List,
    Map,
    PID,
    Port,
    Reference,
    Tuple
  ] do
  def load(data, _name) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  def store(data, _name, _updated_data, _supplemental_data) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  def store_error(data, _name, _reason, _supplemental_data) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end
end
