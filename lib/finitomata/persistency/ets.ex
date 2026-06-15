defmodule Finitomata.Persistency.ETS do
  @moduledoc """
  Built-in in-memory `Finitomata.Persistency` adapter backed by a named ETS table.

  It stores one `{state, payload}` snapshot per FSM (keyed by the FSM name) and reloads
    it when an FSM with the same name starts again. Because the table is owned by a
    long-lived process rather than by the FSM itself, snapshots survive the transient
    restart of an individual FSM (for example after a crash), which makes this adapter a
    zero-boilerplate fit for development, tests, and single-node deployments that only
    need durability for the lifetime of the node.

  > #### In-memory only {: .warning}
  >
  > Snapshots are kept in ETS and are lost when the node stops. Use
  > `Finitomata.Persistency.DETS` for durability across node restarts, or a custom
  > `Finitomata.Persistency` implementation (for example via
  > `Finitomata.Persistency.Persistable`) to target an external database.

  ## Usage

  Add the table owner to your supervision tree and point `use Finitomata` at this module:

  ```elixir
  children = [
    Finitomata.Persistency.ETS,
    {Finitomata.Supervisor, id: MyApp.Fsm}
  ]

  defmodule MyApp.Order do
    use Finitomata, fsm: @fsm, persistency: Finitomata.Persistency.ETS
  end
  ```

  Start FSMs whose name equals the entity id so that the `store` and `load` keys line up:

  ```elixir
  Finitomata.start_fsm(MyApp.Fsm, MyApp.Order, order_id, %MyApp.Order{id: order_id})
  ```

  ## Configuration

  The ETS table name defaults to `#{inspect(__MODULE__)}` and can be overridden:

  ```elixir
  config :finitomata, Finitomata.Persistency.ETS, table: :my_fsm_snapshots
  ```
  """

  @behaviour Finitomata.Persistency

  use GenServer

  alias Finitomata.Persistency.Snapshot

  @default_table __MODULE__

  @doc "The ETS table name in use (configurable via `config :finitomata, #{inspect(__MODULE__)}`)"
  @spec table() :: atom()
  def table, do: Application.get_env(:finitomata, __MODULE__, [])[:table] || @default_table

  @doc "Starts the process owning the snapshot table; add it to your supervision tree"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @impl GenServer
  def init(_opts) do
    table = table()

    ^table =
      :ets.new(table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl Finitomata.Persistency
  def load(arg), do: Snapshot.load(:ets, table(), arg)

  @impl Finitomata.Persistency
  def store(name, payload, info), do: Snapshot.store(:ets, table(), name, payload, info)

  @impl Finitomata.Persistency
  def store_error(name, payload, reason, info),
    do: Snapshot.store_error(:ets, table(), name, payload, reason, info)

  @doc "Reads the snapshot stored for `name`, or `nil`"
  @spec get(Finitomata.fsm_name()) :: Finitomata.Persistency.snapshot() | nil
  def get(name), do: Snapshot.get(:ets, table(), name)

  @doc "Reads the last persisted failure for `name`, or `nil`"
  @spec last_error(Finitomata.fsm_name()) :: Finitomata.Persistency.error() | nil
  def last_error(name), do: Snapshot.last_error(:ets, table(), name)

  @doc "Removes the snapshot and the last error stored for `name`"
  @spec purge(Finitomata.fsm_name()) :: :ok
  def purge(name), do: Snapshot.purge(:ets, table(), name)
end
