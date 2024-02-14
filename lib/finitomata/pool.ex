defmodule Finitomata.Pool do
  @moduledoc """
  Fully asynchronous pool to manage many similar processes, like connections.

  The pool is to be started using `start_pool/1` directly or with `pool_spec/1` in the
    supervision tree.

  `initialize/2` is explicitly separated because usually this is to be done after some
    external service initialization. In a case of `AMQP` connection management, one
    would probably start the connection process and then a pool to manage channels.

  Once `initialize/2` has been called, the `run/3` function might be invoked to
    asynchronously execute the function passed as `actor` to `start_pool/1`.

  If the callbacks `on_result/1` and/or `on_error/1` are defined, they will be invoked
    respectively. Finally, the message to the calling process will be sent, unless
    the third argument in a call to `run/3` is `nil`.
  """
  @moduledoc since: "0.18.0"

  @fsm """
  idle --> |init| ready
  ready --> |do| ready
  ready --> |stop| done
  """

  @pool_size Application.compile_env(:finitomata, :pool_size, System.schedulers_online())
  @actor_prefix Application.compile_env(:finitomata, :pool_worker_prefix, "PoolWorker")

  use Finitomata, fsm: @fsm, auto_terminate: true

  @typedoc "The simple actor function in the pool"
  @type naive_actor :: (term() -> {:ok, term()} | {:error, any()})

  @typedoc "The actor function in the pool, receiving the state as a second argument"
  @type responsive_actor ::
          (term(), Finitomata.State.payload() -> {:ok, term()} | {:error, any()})

  @typedoc "The actor function in the pool"
  @type actor :: naive_actor() | responsive_actor()

  @typedoc "The simple handler of result/error in the pool"
  @type naive_handler :: (term() -> any())

  @typedoc "The actor function in the pool, receiving the state as a second argument"
  @type responsive_handler :: (term(), Finitomata.State.payload() -> any())

  @typedoc "The handler function in the pool"
  @type handler :: naive_handler() | responsive_handler()

  defstate %{
    actor: {StreamData, :constant, &Function.identity/1},
    on_error: {StreamData, :constant, &Function.identity/1},
    on_result: {StreamData, :constant, &Function.identity/1},
    errors: [:term],
    payload: :term
  }

  @doc """
  Starts a pool of asynchronous workers wrapped by an _FSM_.
  """
  @spec start_pool([
          {:id, Finitomata.id()}
          | {:count, pos_integer()}
          | {:actor, actor()}
          | {:on_error, (any() -> any())}
          | {:on_result, (any() -> any())}
        ]) ::
          GenServer.on_start()
  def start_pool(opts \\ []) do
    {id, opts} = Keyword.pop(opts, :id)
    {count, opts} = Keyword.pop(opts, :id, @pool_size)
    start_pool(id, count, opts)
  end

  @spec start_pool(
          id :: Finitomata.id(),
          count :: pos_integer(),
          [{:actor, actor()} | {:on_error, handler()} | {:on_result, handler()}]
          | %{
              required(:actor) => actor(),
              optional(:on_error) => handler(),
              optional(:on_result) => handler()
            }
          | [{:implementation, module()}]
          | %{required(:implementation) => module()}
        ) ::
          GenServer.on_start()
  def start_pool(id, count, state) when is_list(state), do: start_pool(id, count, Map.new(state))

  def start_pool(id, count, %{implementation: impl}) do
    state =
      %{actor: &impl.actor/2}
      |> then(fn spec ->
        if function_exported?(impl, :on_result, 1),
          do: Map.put(spec, :on_result, &impl.on_result/1),
          else: spec
      end)
      |> then(fn spec ->
        if function_exported?(impl, :on_error, 1),
          do: Map.put(spec, :on_error, &impl.on_error/1),
          else: spec
      end)

    start_pool(id, count, state)
  end

  def start_pool(id, count, %{actor: actor} = state)
      when is_function(actor, 1) or is_function(actor, 2) do
    {:ok, state} = Estructura.coerce(__MODULE__, state)

    id
    |> Infinitomata.start_link()
    |> tap(fn _ ->
      Enum.each(
        1..count,
        &Infinitomata.start_fsm(id, "#{@actor_prefix}_#{&1}", Finitomata.Pool, state)
      )
    end)
  end

  @doc """
  Child spec for `Finitomata.Pool` to embed the process into a supervision tree
  """
  @spec pool_spec(keyword()) :: Supervisor.child_spec()
  def pool_spec(opts \\ []) do
    {child_opts, opts} = Keyword.pop(opts, :child_opts, %{})

    child_opts
    |> Map.new()
    |> Map.merge(%{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_pool, [opts]}
    })
  end

  @doc """
  Initializes the started _FSM_s with the same payload, or with what `payload_fun/1`
    would return as many times as the number of workers.
  """
  @spec initialize(Finitomata.id(), (pos_integer() -> any()) | any()) :: :ok
  def initialize(id, payload_fun) when is_function(payload_fun, 1) do
    count = Infinitomata.count(id)

    Enum.each(
      1..count,
      &Infinitomata.transition(id, "#{@actor_prefix}_#{&1}", {:init, payload_fun.(&1)})
    )
  end

  def initialize(id, payload) do
    initialize(id, fn _ -> payload end)
  end

  @doc """
  The runner for the `actor` function with the specified payload.

  Basically, upon calling `run/3`, the following chain of calls would have happened:

  1. `actor.(payload, state)` (or `actor.(payload)` if the function of arity one had been given)
  2. `on_result(result, state)` / `on_error(result, state)` if callbacks are specified
  3. the message of the shape `{:transition, :success/:failure, self(), {payload, result, on_result/on_error}})` 
     will be sent to `pid` unless `nil` given as a third argument 
  """
  @spec run(Finitomata.id(), Finitomata.event_payload(), pid()) :: :ok
  def run(id, payload, pid \\ self()) do
    Infinitomata.transition(id, Infinitomata.random(id), {:do, {pid, payload}})
  end

  @doc false
  def on_transition(:idle, :init, payload, %{actor: _actor} = state) do
    {:ok, :ready, put_in(state, [:payload], payload)}
  end

  @doc false
  def on_transition(:ready, :do, {pid, payload}, %{actor: actor} = state) do
    state =
      case invoke(actor, payload, state.payload) do
        {:ok, result} ->
          on_result = invoke(state.on_result, result, state.payload)

          if not is_nil(pid),
            do: send(pid, {:transition, :success, self(), {payload, result, on_result}})

          state

        {:error, reason} ->
          on_error = invoke(state.on_error, reason, state.payload)

          if not is_nil(pid),
            do: send(pid, {:transition, :failure, self(), {payload, reason, on_error}})

          update_in(state, [:errors], &[reason | &1])
      end

    {:ok, :ready, state}
  end

  defp invoke(fun, arg1, arg2) do
    case fun do
      nil -> nil
      f when is_function(f, 1) -> f.(arg1)
      f when is_function(f, 2) -> f.(arg1, arg2)
    end
  end
end
