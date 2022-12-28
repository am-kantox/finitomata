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
  def load(data)

  @doc "Persists the transitioned entity to some external storage"
  def store(data, info)

  @doc "Persists the error happened while an attempt to transition the entity"
  def store_error(data, reason, info)
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
    Reference
  ] do
  def load(data) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  def store(data, _info) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  def store_error(data, _reason, _info) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end
end

defimpl Finitomata.Persistency.Persistable, for: Tuple do
  alias Finitomata.Persistency.Persistable, as: Proto

  def load({module, fields}) when is_list(fields),
    do: load({module, Map.new(fields)})

  def load({module, fields}) when is_map(fields) do
    defines_struct? = fn module ->
      :functions
      |> module.__info__()
      |> Keyword.take([:__struct__])
      |> Keyword.values() == [0, 1]
    end

    with true <- Code.ensure_loaded?(module),
         true <- defines_struct?.(module),
         %^module{} = result <- struct(module, fields),
         impl when not is_nil(impl) <- Proto.impl_for(result) do
      Proto.load(result)
    else
      _ -> nil
    end
  end

  def load({module, loader}) when is_function(loader, 1) do
    loader.(module)
  end

  def store({data, storer}, info) when is_function(storer, 2) do
    storer.(data, info)
  end

  def store_error({data, storer}, reason, info) when is_function(storer, 3) do
    storer.(data, reason, info)
  end
end
