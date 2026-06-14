defmodule Finitomata.Persistency.Snapshot do
  @moduledoc false

  # Shared implementation backing the built-in `Finitomata.Persistency.ETS` and
  #   `Finitomata.Persistency.DETS` adapters.
  #
  # Both adapters keep a single `{state, payload}` snapshot per FSM, keyed by the FSM
  #   name, plus an optional last-error record. They differ only in the storage `kind`
  #   (`:ets` for in-memory, `:dets` for disk-backed); the `:ets`/`:dets` read/write
  #   primitives share the same `{key, value}` shape, so the orchestration lives here
  #   once and each adapter passes its own `kind` and resolved table name.
  #
  # Key derivation follows the contract `Finitomata.Engine` actually uses:
  #   * `store/store_error` receive the fully-qualified FSM `name`, normalized with
  #     `idfy/1` (the registered plain name);
  #   * `load` receives the `{type, fields}` tuple the engine builds from the start
  #     payload, and the storage key is taken from `fields[:id]`.
  #   These coincide whenever the FSM name equals the entity id, which is the
  #   documented usage pattern (see `Finitomata.Persistency`).

  alias Finitomata.{State, Transition}

  @error_tag :__finitomata_error__

  @typedoc "The storage kind backing an adapter"
  @type kind :: :ets | :dets

  @typedoc "A persisted FSM snapshot: the current state and the carried payload"
  @type snapshot :: {Transition.state() | nil, State.payload()}

  @typedoc "A persisted transition failure"
  @type error :: %{reason: any(), info: map(), payload: State.payload()}

  @doc "Normalizes a (possibly registered) FSM name into the bare storage key"
  @spec idfy(Finitomata.fsm_name()) :: term()
  def idfy({:via, _registry, {_registry_name, name}}), do: name
  def idfy(name), do: name

  @doc """
  Loads the snapshot for the entity described by the engine's `{type, fields}` tuple.

  Returns `{:loaded, {state, payload}}` when a snapshot exists, otherwise
    `{:created, {nil, fresh_payload}}` where `fresh_payload` is reconstructed from the
    start payload. The first snapshot is written by the entry transition.
  """
  @spec load(kind(), atom(), term()) :: {:loaded | :created, snapshot()}
  def load(kind, table, {_type, _fields} = arg) do
    case safe_lookup(kind, table, load_key(arg)) do
      [{_key, {_state, _payload} = snapshot}] -> {:loaded, snapshot}
      _ -> {:created, {nil, fresh(arg)}}
    end
  end

  def load(kind, table, id) do
    case safe_lookup(kind, table, id) do
      [{_key, {_state, _payload} = snapshot}] -> {:loaded, snapshot}
      _ -> {:created, {nil, %{}}}
    end
  end

  @doc "Persists the post-transition `{to, payload}` snapshot keyed by the FSM name"
  @spec store(kind(), atom(), Finitomata.fsm_name(), State.payload(), map()) :: :ok
  def store(kind, table, name, payload, %{to: to}) do
    put(kind, table, {idfy(name), {to, payload}})
    :ok
  end

  @doc "Persists a transition failure keyed by the FSM name; returns `:ok`"
  @spec store_error(kind(), atom(), Finitomata.fsm_name(), State.payload(), any(), map()) :: :ok
  def store_error(kind, table, name, payload, reason, info) do
    put(kind, table, {{@error_tag, idfy(name)}, %{reason: reason, info: info, payload: payload}})
    :ok
  end

  @doc "Reads the snapshot stored for `name`, or `nil`"
  @spec get(kind(), atom(), Finitomata.fsm_name()) :: snapshot() | nil
  def get(kind, table, name) do
    case safe_lookup(kind, table, idfy(name)) do
      [{_key, {_state, _payload} = snapshot}] -> snapshot
      _ -> nil
    end
  end

  @doc "Reads the last persisted failure for `name`, or `nil`"
  @spec last_error(kind(), atom(), Finitomata.fsm_name()) :: error() | nil
  def last_error(kind, table, name) do
    case safe_lookup(kind, table, {@error_tag, idfy(name)}) do
      [{_key, %{} = error}] -> error
      _ -> nil
    end
  end

  @doc "Removes the snapshot and the last error stored for `name`"
  @spec purge(kind(), atom(), Finitomata.fsm_name()) :: :ok
  def purge(kind, table, name) do
    key = idfy(name)
    delete(kind, table, key)
    delete(kind, table, {@error_tag, key})
    :ok
  end

  # The engine injects the FSM `name` (the fully-qualified via-tuple) as `fields[:id]`
  #   when the start payload carries no id of its own, while `store/store_error` key by
  #   `idfy(name)`. Normalizing here keeps both sides on the same plain key.
  @spec load_key(term()) :: term()
  defp load_key({_type, fields}), do: fields |> to_map() |> Map.get(:id) |> idfy()

  @spec fresh(term()) :: State.payload()
  defp fresh({type, fields}) do
    map = to_map(fields)

    if struct_module?(type),
      do: struct(type, Map.delete(map, :id)),
      else: Map.delete(map, :id)
  end

  @spec to_map(term()) :: map()
  defp to_map(fields) when is_list(fields), do: Map.new(fields)
  defp to_map(%{} = fields), do: fields
  defp to_map(_other), do: %{}

  @spec struct_module?(term()) :: boolean()
  defp struct_module?(type) when is_atom(type),
    do: Code.ensure_loaded?(type) and function_exported?(type, :__struct__, 0)

  defp struct_module?(_other), do: false

  @spec safe_lookup(kind(), atom(), term()) :: [tuple()]
  defp safe_lookup(:ets, table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError -> []
  end

  defp safe_lookup(:dets, table, key) do
    case :dets.lookup(table, key) do
      list when is_list(list) -> list
      _other -> []
    end
  rescue
    _error -> []
  end

  @spec put(kind(), atom(), tuple()) :: :ok
  defp put(:ets, table, object) do
    if :ets.whereis(table) != :undefined, do: :ets.insert(table, object)
    :ok
  end

  defp put(:dets, table, object) do
    _ = :dets.insert(table, object)
    :ok
  rescue
    _error -> :ok
  end

  @spec delete(kind(), atom(), term()) :: :ok
  defp delete(:ets, table, key) do
    if :ets.whereis(table) != :undefined, do: :ets.delete(table, key)
    :ok
  end

  defp delete(:dets, table, key) do
    _ = :dets.delete(table, key)
    :ok
  rescue
    _error -> :ok
  end
end
