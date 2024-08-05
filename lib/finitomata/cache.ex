defmodule Finitomata.Cache do
  @moduledoc since: "0.26.0"
  @moduledoc """
    The self-curing cache based on `Finitomata` implementation
  """

  defmodule State do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    @spec config(pid :: pid()) :: keyword()
    def config(pid), do: GenServer.call(pid, :state)

    @impl GenServer
    def init(opts), do: {:ok, opts}

    @impl GenServer
    def handle_call(:state, _from, opts), do: {:reply, opts, opts}
  end

  defmodule Value do
    @moduledoc false

    @fsm """
    idle --> |init!| ready
    ready --> |set| set
    set --> |ready!| ready
    ready --> |stop| done
    """

    use Finitomata, fsm: @fsm, auto_terminate: true, timer: 1, impl_for: [:on_transition]

    defstruct [:value, :getter, :live?, :ttl]

    @impl Finitomata
    def on_transition(:idle, :init, ttl, state) when is_integer(ttl) and ttl > 0 do
      {:ok, :ready, %__MODULE__{state | value: :error, ttl: ttl}}
    end

    @impl Finitomata
    def on_transition(:ready, :set, {getter, value}, state) when is_function(getter, 0) do
      {:ok, :set, %__MODULE__{state | value: {:ok, value}, getter: getter}}
    end

    def on_transition(:ready, :set, getter, state) when is_function(getter, 0) do
      on_transition(:ready, :set, {getter, getter.()}, state)
    end

    def on_transition(:ready, :set, _, state) do
      {:ok, :set, %__MODULE__{state | value: :error}}
    end

    @impl Finitomata
    def on_timer(:ready, %{timer: {_, 1}, payload: %{ttl: ttl}}) do
      {:reschedule, ttl}
    end

    def on_timer(:ready, %{payload: %{getter: getter, live?: true} = payload} = state) do
      Logger.debug(
        "Cache value for " <>
          inspect(Finitomata.State.human_readable_name(state, false)) <> " is to be renewed"
      )

      {:transition, {:set, getter}, payload}
    end

    def on_timer(:ready, %{payload: %{live?: false} = payload} = state) do
      Logger.debug(
        "Cache value for " <>
          inspect(Finitomata.State.human_readable_name(state, false)) <> " is to be unset"
      )

      {:transition, {:set, :error}, payload}
    end

    def on_timer(_, state), do: {:ok, state.payload}
  end

  require Logger

  schema = [
    id: [
      required: true,
      type: :any,
      doc:
        "The unique `ID` of this _Finitomata_ “branch,” when `nil` the `#{inspect(__MODULE__)}` value would be used"
    ],
    ttl: [
      required: true,
      type: :pos_integer,
      doc:
        "The default time-to-live value in seconds, after which the value would be either revalidated or discarded"
    ],
    type: [
      required: false,
      default: Infinitomata,
      type: {:custom, Finitomata, :behaviour, [Finitomata.Supervisor]},
      doc:
        "The actual `Finitomata.Supervisor` implementation (typically, `Finitomata` or `Infinitomata`)"
    ],
    live?: [
      required: false,
      default: false,
      type: :boolean,
      doc:
        "When `true`, the value will be automatically renewed upon expiration (and discarded otherwise)"
    ]
  ]

  @schema NimbleOptions.new!(schema)

  use Supervisor

  @doc """
  Supervision tree embedder.

  ## Options to `Finitomata.Cache.start_link/1`

  #{NimbleOptions.docs(@schema)}
  """
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @schema)
    Supervisor.start_link(__MODULE__, opts, name: opts |> Keyword.fetch!(:id) |> name())
  end

  @impl Supervisor
  @doc false
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    type = Keyword.fetch!(opts, :type)

    children = [
      {State, opts},
      {type, id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec opts(id :: Finitomata.id()) :: [unquote(NimbleOptions.option_typespec(@schema))]
  @doc false
  # {{Finitomata.Distributed.Supervisor, Finitomata.Cache}, #PID<0.5210.0>,
  #  :supervisor, [Finitomata.Distributed.Supervisor]},
  # {Finitomata.Cache.State, #PID<0.5209.0>, :worker, [Finitomata.Cache.State]}
  defp opts(id) do
    id
    |> name()
    |> Supervisor.which_children()
    |> Enum.find(&match?({Finitomata.Cache.State, _pid, :worker, _}, &1))
    |> case do
      {Finitomata.Cache.State, pid, :worker, _} -> State.config(pid)
      _ -> []
    end
  end

  @doc false
  @spec name(id :: Finitomata.id()) :: module()
  defp name(id), do: Finitomata.Supervisor.cache_name(id)

  @doc """
  Retrieves the value either cached or via `getter/0` anonymous function and caches it.

  Spawns the respective _Finitomata_ instance if needed.
  """
  @spec get(
          id :: Finitomata.id(),
          key :: any(),
          opts :: [
            {:getter, (-> value)}
            | {:live?, boolean()}
            | {:reset, boolean()}
            | {:ttl, pos_integer()}
          ]
        ) :: {:ok, value} | :error
        when value: any()
  def get(id, key, opts \\ []) do
    opts = id |> opts() |> Keyword.merge(opts)
    {reset, opts} = Keyword.pop(opts, :reset, false)
    {getter, opts} = Keyword.pop(opts, :getter, nil)
    ttl = Keyword.fetch!(opts, :ttl)
    live? = Keyword.fetch!(opts, :live?)
    type = Keyword.fetch!(opts, :type)

    id
    |> type.start_fsm(
      key,
      Value,
      struct!(Value, getter: getter, live?: live?, ttl: ttl)
    )
    |> case do
      {:ok, _pid} ->
        if is_function(getter, 0) do
          {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, &1}}))}
        else
          Logger.warning("Initial call to `Finitomata.Cache.get/3` must contain a getter")
          type.transition(id, key, :stop)
          :error
        end

      {:error, {:already_started, _pid}} ->
        case {reset, getter, type.state(id, key, :payload)} do
          {false, nil, %{value: {:ok, value}}} ->
            {:ok, value}

          {false, getter, %{value: {:ok, value}}} ->
            Logger.warning(
              "Setting a `getter` without `reset` does not make any sense, got: " <>
                inspect(getter)
            )

            {:ok, value}

          {_, nil, %{getter: getter}} when is_function(getter, 0) ->
            {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, &1}}))}

          {_, getter, %{}} when is_function(getter, 0) ->
            {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, &1}}))}

          _ ->
            Logger.warning("`getter` must be either a function of arity `0` or `nil`")
            :error
        end

      {:error, error} ->
        Logger.warning("Could not start FSM. Error: " <> inspect(error))
        :error
    end
  end

  @doc """
  Erases the cache assotiated with `key`.
  """
  @spec erase(id :: Finitomata.id(), key :: any()) :: :ok
  def erase(id, key) do
    type = id |> opts() |> Keyword.fetch!(:type)
    type.transition(id, key, :stop)
  end
end
