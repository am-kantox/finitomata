defmodule Finitomata.StateCache do
  @moduledoc false

  # Caches the latest FSM payload so that `Finitomata.state/3` invoked with
  #   `:cached` or `:payload` can return it without a `GenServer.call/3` round-trip.
  #
  # Historically this cache was backed by `:persistent_term`. That is a poor fit for
  #   frequently updated, per-instance data: every `:persistent_term.put/2` (or erase)
  #   schedules a global scan proportional to the number of processes/terms, which is
  #   exactly the wrong cost model for a value rewritten on every transition.
  #
  # The default backend is now an ETS table owned per `Finitomata` supervision tree,
  #   so writes are cheap and the whole cache is dropped automatically when the tree
  #   goes down. Set `config :finitomata, :cache_backend, :persistent_term` to restore
  #   the legacy behaviour.

  use GenServer

  @backend Application.compile_env(:finitomata, :cache_backend, :ets)

  @typedoc "The cache backend in use"
  @type backend :: :ets | :persistent_term

  @doc false
  @spec backend :: backend()
  def backend, do: @backend

  @doc false
  @spec start_link(Finitomata.id()) :: GenServer.on_start()
  def start_link(id \\ nil), do: GenServer.start_link(__MODULE__, id, name: name(id))

  @doc false
  @spec child_spec(Finitomata.id()) :: Supervisor.child_spec()
  def child_spec(id),
    do: %{id: {__MODULE__, id}, start: {__MODULE__, :start_link, [id]}}

  @doc false
  @spec name(Finitomata.id()) :: module()
  def name(id \\ nil), do: Finitomata.Supervisor.state_cache_name(id)

  if @backend == :ets do
    @impl GenServer
    def init(id) do
      table = name(id)

      ^table =
        :ets.new(table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      {:ok, table}
    end
  else
    @impl GenServer
    def init(_id), do: :ignore
  end

  @doc false
  @spec get(Finitomata.id(), term(), term()) :: term()
  def get(id, key, default \\ nil)

  if @backend == :ets do
    def get(id, key, default) do
      case safe_lookup(name(id), key) do
        [{^key, value}] -> value
        _ -> default
      end
    end
  else
    def get(_id, key, default), do: :persistent_term.get({Finitomata, key}, default)
  end

  @doc false
  @spec put(Finitomata.id(), term(), term()) :: :ok
  if @backend == :ets do
    def put(id, key, value) do
      table = name(id)
      if :ets.whereis(table) != :undefined, do: :ets.insert(table, {key, value})
      :ok
    end
  else
    def put(_id, key, value) do
      :persistent_term.put({Finitomata, key}, value)
      :ok
    end
  end

  @doc false
  @spec delete(Finitomata.id(), term()) :: :ok
  if @backend == :ets do
    def delete(id, key) do
      table = name(id)
      if :ets.whereis(table) != :undefined, do: :ets.delete(table, key)
      :ok
    end
  else
    def delete(_id, key) do
      _ = :persistent_term.erase({Finitomata, key})
      :ok
    end
  end

  if @backend == :ets do
    @spec safe_lookup(:ets.table(), term()) :: [tuple()]
    defp safe_lookup(table, key) do
      :ets.lookup(table, key)
    rescue
      ArgumentError -> []
    end
  end
end
