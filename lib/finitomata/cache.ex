defmodule Finitomata.Cache do
  @moduledoc since: "0.26.0"
  @moduledoc """
    The self-curing cache based on `Finitomata` implementation
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

    defstruct value: :error,
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
        when is_function(getter, 0) do
      {:ok, :set, %__MODULE__{state | value: {:ok, value}, getter: getter, live?: live?}}
    end

    def on_transition(:ready, :set, getter, %__MODULE__{} = state) when is_function(getter, 0) do
      on_transition(:ready, :set, {getter, state.live?, getter.()}, state)
    end

    def on_transition(:ready, :set, _, %__MODULE__{} = state) do
      {:ok, :set, %__MODULE__{state | value: :error}}
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

  @doc """
  Supervision tree embedder.

  ## Options to `Finitomata.Cache.start_link/1`

  #{NimbleOptions.docs(@schema)}
  """
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @schema)
    id = Keyword.fetch!(opts, :id)
    type = Keyword.fetch!(opts, :type)
    Config.init(id, opts)
    type.start_link(id)
  end

  @spec opts(id :: Finitomata.id()) :: [unquote(NimbleOptions.option_typespec(@schema))]
  @doc false
  defp opts(id), do: Config.get(id)

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
          {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, live?, &1}}))}
        else
          Logger.warning("Initial call to `Finitomata.Cache.get/3` must contain a getter")
          type.transition(id, key, :stop)
          :error
        end

      {:error, {:already_started, _pid}} ->
        case {reset, getter, type.state(id, key, :payload)} do
          {false, nil, %Value{value: {:ok, value}}} ->
            {:ok, value}

          {false, getter, %Value{value: {:ok, value}}} ->
            Logger.warning(
              "Setting a `getter` without `reset` does not make any sense, got: " <>
                inspect(getter)
            )

            {:ok, value}

          {_, nil, %Value{getter: getter}} when is_function(getter, 0) ->
            {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, live?, &1}}))}

          {_, getter, %Value{}} when is_function(getter, 0) ->
            {:ok, tap(getter.(), &type.transition(id, key, {:set, {getter, live?, &1}}))}

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
