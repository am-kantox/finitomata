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
  def load(data, opts \\ [])

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
  @dialyzer {:no_return, {:load, 1}}
  @dialyzer {:no_return, {:load, 2}}
  def load(data, _opts \\ []) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  @dialyzer {:no_return, {:store, 2}}
  def store(data, _info) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end

  @dialyzer {:no_return, {:store_error, 3}}
  def store_error(data, _reason, _info) do
    raise Protocol.UndefinedError, protocol: __MODULE__, value: data
  end
end

defimpl Finitomata.Persistency.Persistable, for: Tuple do
  alias Finitomata.Persistency.Persistable, as: Proto

  def load({module, fields}, opts) when is_list(fields),
    do: load({module, Map.new(fields)}, opts)

  def load({module, fields}, opts) when is_map(fields) do
    defines_struct? = fn module ->
      :functions
      |> module.__info__()
      |> Keyword.take([:__struct__])
      |> Keyword.values() == [0, 1]
    end

    with {:module, ^module} <- Code.ensure_compiled(module),
         {:struct, true} <- {:struct, defines_struct?.(module)},
         %^module{} = result <- struct(module, fields),
         impl when not is_nil(impl) <- Proto.impl_for(result) do
      case result do
        %^module{id: _id} ->
          Proto.load(result, opts)

        %^module{} ->
          id = Keyword.get_lazy(opts, :id, fn -> Map.get(fields, :id) end)
          impl.load(result, id: id)
      end
    else
      {:struct, false} -> Proto.load({module, fields})
      _ -> {:unknown, nil}
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
