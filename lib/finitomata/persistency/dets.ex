defmodule Finitomata.Persistency.DETS do
  @moduledoc """
  Built-in disk-durable `Finitomata.Persistency` adapter backed by a `:dets` file.

  It behaves exactly like `Finitomata.Persistency.ETS` (one `{state, payload}` snapshot
    per FSM, keyed by the FSM name) but the table is persisted to disk, so snapshots
    survive a full node restart. Both adapters are OTP built-ins and add no dependencies.

  > #### Single node {: .info}
  >
  > `:dets` is a single-node, single-file store with a 2GB file-size limit. For
  > multi-node or large-scale persistence, back the FSM with a database via a custom
  > `Finitomata.Persistency` implementation (for example through
  > `Finitomata.Persistency.Persistable`).

  ## Usage

  Add the table owner to your supervision tree and point `use Finitomata` at this module:

  ```elixir
  children = [
    Finitomata.Persistency.DETS,
    {Finitomata.Supervisor, id: MyApp.Fsm}
  ]

  defmodule MyApp.Order do
    use Finitomata, fsm: @fsm, persistency: Finitomata.Persistency.DETS
  end
  ```

  ## Configuration

  The `:dets` file path (and optionally the table name) are configurable. The default
    path lives under `System.tmp_dir!/0`; set a stable location for production:

  ```elixir
  config :finitomata, Finitomata.Persistency.DETS,
    file: "/var/lib/my_app/finitomata.dets",
    table: :my_fsm_snapshots
  ```
  """

  @behaviour Finitomata.Persistency

  use GenServer

  alias Finitomata.Persistency.Snapshot

  @default_table __MODULE__

  @doc "The `:dets` table name in use (configurable via `config :finitomata, #{inspect(__MODULE__)}`)"
  @spec table() :: atom()
  def table, do: Application.get_env(:finitomata, __MODULE__, [])[:table] || @default_table

  @doc "The `:dets` file path in use (configurable via `config :finitomata, #{inspect(__MODULE__)}`)"
  @spec file() :: String.t()
  def file do
    Application.get_env(:finitomata, __MODULE__, [])[:file] ||
      Path.join(System.tmp_dir!(), "finitomata_persistency.dets")
  end

  @doc "Starts the process owning the snapshot file; add it to your supervision tree"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @impl GenServer
  def init(_opts) do
    table = table()
    path = file()
    _ = path |> Path.dirname() |> File.mkdir_p()

    {:ok, ^table} =
      :dets.open_file(table, file: String.to_charlist(path), type: :set, auto_save: 5_000)

    {:ok, %{table: table}}
  end

  @impl GenServer
  def terminate(_reason, %{table: table}), do: :dets.close(table)

  @impl Finitomata.Persistency
  def load(arg), do: Snapshot.load(:dets, table(), arg)

  @impl Finitomata.Persistency
  def store(name, payload, info), do: Snapshot.store(:dets, table(), name, payload, info)

  @impl Finitomata.Persistency
  def store_error(name, payload, reason, info),
    do: Snapshot.store_error(:dets, table(), name, payload, reason, info)

  @doc "Reads the snapshot stored for `name`, or `nil`"
  @spec get(Finitomata.fsm_name()) :: Snapshot.snapshot() | nil
  def get(name), do: Snapshot.get(:dets, table(), name)

  @doc "Reads the last persisted failure for `name`, or `nil`"
  @spec last_error(Finitomata.fsm_name()) :: Snapshot.error() | nil
  def last_error(name), do: Snapshot.last_error(:dets, table(), name)

  @doc "Removes the snapshot and the last error stored for `name`"
  @spec purge(Finitomata.fsm_name()) :: :ok
  def purge(name), do: Snapshot.purge(:dets, table(), name)

  @doc "Flushes pending writes to disk"
  @spec sync() :: :ok | {:error, term()}
  def sync, do: :dets.sync(table())
end
