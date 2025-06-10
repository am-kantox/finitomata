defmodule Finitomata.Cache do
  @moduledoc since: "0.26.0"
  @moduledoc """
  The self-curing cache based on `Finitomata` implementation.

  This implementation should not be chosen for typical caching scenarios,
    use [`cachex`](https://hexdocs.pm/cachex) and/or [`con_cache`](https://hexdocs.pm/con_cache)
    instead.

  The use-case for this implementation would be somewhat like a self-updated local replica
    of the remote data. Unlike typical cache implementations, this one might keep the cached
    values up-to-date, configured by `ttl:` argument. Bsaed on processes (backed by `Finitomata`,)
    this implementation updates itself periodically, making the value retrieval almost instant.

  Consider a remote service supplying currency exchange rates by polling. One might instruct
    `Finitomata.Cache` to retrieve values periodically (say, once per a minute,) and then
    the consumers of this cache would be able to retrieve the up-to-date values locally without
    a penalty of getting a value after a long period (cache miss.)

  First of all, the `Finitomata.Cache` implementation should be added to a supervision tree

  ```elixir
    {Finitomata.Cache, [
      [id: MyCache, ttl: 60_000, live?: true, type: Infinitomata, getter: &MyMod.getter/1]]}
  ```

  Once the supervisor is started, the values might be retrieven as

  ```elixir
    Finitomata.Cache.get(MyCache, :my_key_1, live?: false) # use default getter
    Finitomata.Cache.get(MyCache, :my_key, getter: fn _ -> ExtService.get(:my_key) end)
  ```
  """

  defmodule Config do
    @moduledoc false

    @spec init(id :: Finitomata.id(), opts :: keyword()) :: :ok
    def init(id, opts \\ []) do
      :persistent_term.put({__MODULE__, id}, opts)
    end

    @spec get(id :: Finitomata.id()) :: keyword()
    def get(id), do: :persistent_term.get({__MODULE__, id}, [])
  end

  defmodule Value do
    @moduledoc false

    @fsm """
    idle --> |init!| ready
    ready --> |set| set
    set --> |ready!| ready
    ready --> |stop| done
    """

    use Finitomata,
      fsm: @fsm,
      auto_terminate: true,
      timer: 1,
      impl_for: [:on_transition],
      listener: :mox

    defstruct key: nil,
              value: :error,
              since: nil,
              getter: nil,
              live?: false,
              ttl: Application.compile_env(:finitomata, :cache_ttl, 5_000)

    @impl Finitomata
    def on_transition(:idle, :init!, _nil, %Value{} = state) do
      {:ok, :ready, state}
    end

    def on_transition(:idle, :init!, _nil, state) do
      {:ok, :ready, struct!(__MODULE__, state)}
    end

    @impl Finitomata
    def on_transition(:ready, :set, {getter, live?, value}, %__MODULE__{} = state)
        when is_function(getter, 1) do
      {:ok, :set,
       %{
         state
         | since: DateTime.utc_now(),
           value: {:ok, value},
           getter: getter,
           live?: live?
       }}
    end

    def on_transition(:ready, :set, getter, %__MODULE__{key: key} = state)
        when is_function(getter, 1) do
      on_transition(:ready, :set, {getter, state.live?, getter.(key)}, state)
    end

    def on_transition(:ready, :set, _, %__MODULE__{} = state) do
      {:ok, :set, %{state | since: DateTime.utc_now(), value: :error}}
    end

    @impl Finitomata
    def on_timer(:ready, %{timer: {_, 1}, payload: %__MODULE__{ttl: ttl}}) do
      {:reschedule, ttl}
    end

    def on_timer(:ready, %{payload: %__MODULE__{getter: getter, live?: true} = payload} = state) do
      Logger.debug(
        "Cache value for " <>
          inspect(Finitomata.State.human_readable_name(state, false)) <> " is to be renewed"
      )

      {:transition, {:set, getter}, payload}
    end

    def on_timer(:ready, %{payload: %__MODULE__{live?: false} = payload} = state) do
      Logger.debug(
        "Cache value for " <>
          inspect(Finitomata.State.human_readable_name(state, false)) <> " is to be unset"
      )

      {:transition, {:set, :error}, payload}
    end

    def on_timer(_, %{payload: payload}), do: {:ok, payload}
  end

  require Logger

  schema = [
    id: [
      required: true,
      type: :any,
      doc:
        "The unique `ID` of this _Finitomata_ “branch,” when `nil` the `#{inspect(__MODULE__)}` value would be used"
    ],
    type: [
      required: false,
      default: Infinitomata,
      type: {:custom, Finitomata, :behaviour, [Finitomata.Supervisor]},
      doc:
        "The actual `Finitomata.Supervisor` implementation (typically, `Finitomata` or `Infinitomata`)"
    ],
    ttl: [
      required: true,
      type: :pos_integer,
      doc:
        "The default time-to-live value in seconds, after which the value would be either revalidated or discarded"
    ],
    live?: [
      required: false,
      default: false,
      type: :boolean,
      doc:
        "When `true`, the value will be automatically renewed upon expiration (and discarded otherwise)"
    ],
    getter: [
      required: false,
      default: nil,
      type: {:or, [{:fun, 1}, {:in, [nil]}]},
      doc:
        "The shared for all instances getter returning a value based on the name of the instance, used as a key"
    ]
  ]

  @schema NimbleOptions.new!(schema)

  @doc """
  Supervision tree embedder.

  ## Options to `Finitomata.Cache.start_link/1`

  #{NimbleOptions.docs(@schema)}
  """
  @spec start_link([unquote(NimbleOptions.option_typespec(@schema))]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @schema)
    id = Keyword.fetch!(opts, :id)
    type = Keyword.fetch!(opts, :type)
    Config.init(id, opts)
    type.start_link(id)
  end

  @spec child_spec([unquote(NimbleOptions.option_typespec(@schema))]) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @schema)
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec opts(id :: Finitomata.id()) :: [unquote(NimbleOptions.option_typespec(@schema))]
  @doc false
  defp opts(id), do: Config.get(id)

  @doc """
  Retrieves the value either cached or via `getter/1` anonymous function and caches it.

  Spawns the respective _Finitomata_ instance if needed.
  """
  @spec get(
          id :: Finitomata.id(),
          key :: key,
          opts :: [
            {:getter, (key -> value)}
            | {:live?, boolean()}
            | {:reset, boolean()}
            | {:ttl, pos_integer()}
          ]
        ) :: {DateTime.t(), value} | {:instant, value} | :error
        when key: any(), value: any()
  def get(id, key, opts \\ []) do
    opts = id |> opts() |> Keyword.merge(opts)
    {reset, opts} = Keyword.pop(opts, :reset, false)
    {getter, opts} = Keyword.pop(opts, :getter, nil)
    ttl = Keyword.fetch!(opts, :ttl)
    live? = Keyword.fetch!(opts, :live?)
    type = Keyword.fetch!(opts, :type)

    maybe_start =
      if not type.alive?(id, key) do
        type.start_fsm(
          id,
          key,
          Value,
          struct!(Value, key: key, getter: getter, live?: live?, ttl: ttl)
        )
      end

    case maybe_start do
      {:ok, _pid} ->
        if is_function(getter, 1) do
          {:created, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}
        else
          Logger.error("Initial call to `Finitomata.Cache.get/3` must contain a getter")
          type.transition(id, key, :stop)
          :error
        end

      {:error, error} when not is_tuple(error) ->
        Logger.warning("Could not start FSM. Error: " <> inspect(error))
        :error

      # nil | {:error, {:already_started, _pid}}
      _ ->
        case {reset, getter, type.state(id, key, :payload)} do
          {false, nil, %Value{since: since, value: {:ok, value}}} ->
            {since, value}

          {false, getter, %Value{since: since, value: {:ok, value}}} ->
            Logger.warning(
              "Setting a `getter` without `reset` does not make any sense, got: " <>
                inspect(getter)
            )

            {since, value}

          {_, getter, %Value{}} when is_function(getter, 1) ->
            {:instant, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}

          {_, nil, %Value{getter: getter}} when is_function(getter, 1) ->
            {:instant, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}

          _ ->
            Logger.warning("`getter` must be either a function of arity `0` or `nil`")
            :error
        end
    end
  end

  @doc false
  @spec get_naive(
          id :: Finitomata.id(),
          key :: key,
          opts :: [
            {:getter, (key -> value)}
            | {:live?, boolean()}
            | {:reset, boolean()}
            | {:ttl, pos_integer()}
          ]
        ) :: {DateTime.t(), value} | {:instant, value} | :error
        when key: any(), value: any()
  def get_naive(id, key, opts \\ []) do
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
      struct!(Value, key: key, getter: getter, live?: live?, ttl: ttl)
    )
    |> case do
      {:ok, _pid} ->
        if is_function(getter, 1) do
          {:created, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}
        else
          Logger.warning("Initial call to `Finitomata.Cache.get/3` must contain a getter")
          type.transition(id, key, :stop)
          :error
        end

      {:error, {:already_started, _pid}} ->
        case {reset, getter, type.state(id, key, :payload)} do
          {false, nil, %Value{since: since, value: {:ok, value}}} ->
            {since, value}

          {false, getter, %Value{since: since, value: {:ok, value}}} ->
            Logger.warning(
              "Setting a `getter` without `reset` does not make any sense, got: " <>
                inspect(getter)
            )

            {since, value}

          {_, getter, %Value{}} when is_function(getter, 1) ->
            {:instant, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}

          {_, nil, %Value{getter: getter}} when is_function(getter, 1) ->
            {:instant, tap(getter.(key), &type.transition(id, key, {:set, {getter, live?, &1}}))}

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
