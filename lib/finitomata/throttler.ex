defmodule Finitomata.Throttler do
  @moduledoc """
  The internal definition of the call to throttle.

  `Finitomata.Throttler.call/3` is a blocking call similar to `GenServer.call/3`, but
    served by the underlying `GenStage` producer-consumer pair.

  Despite this implementation of throttling based on `GenStage` is provided
    mostly for internal needs, it is generic enough to use wherever. Use the childspec
    `{Finitomata.Throttler, name: name, initial: [], max_demand: 3, interval: 1_000}`
    to start a throttling process and `Finitomata.Throttler.call/3` to perform throttled
    synchronous calls from different processes.

  ### Usage

  ```elixir
  {:ok, pid} = Finitomata.Throttler.start_link(name: Throttler)

  Finitomata.Throttler.call(Throttler, {IO, :inspect, [42]})
  42

  #⇒ %Finitomata.Throttler{
  #   from: {#PID<0.335.0>, #Reference<0.3154300821.2643722246.59214>},
  #   fun: {IO, :inspect},
  #   args: ~c"*",
  #   result: 42,
  #   duration: 192402,
  #   payload: nil
  # }  
  ```
  """

  @typedoc "The _in/out_ parameter for calls to `Finitomata.Throttler.call/3`"
  @type t :: %{
          __struct__: Finitomata.Throttler,
          from: GenServer.from(),
          fun: (keyword() -> any()),
          args: keyword(),
          result: any(),
          duration: pos_integer(),
          payload: any()
        }

  @typedoc "The simplified _in_ parameter for calls to `Finitomata.Throttler.call/3`"
  @type throttlee :: t() | {(keyword() -> any()), [any()]}

  defstruct ~w|from fun args result duration payload|a

  use Supervisor

  require Logger

  alias Finitomata.Throttler.{Consumer, Producer}

  @doc """
  Starts the throttler with the underlying producer-consumer stages.

  Accepted options are:

  - `name` the base name for the throttler to be used in calls to `call/3`
  - `initial` the initial load of requests (avoid using it unless really needed)
  - `max_demand`, `initial` the options to be passed directly to `GenStage`’s consumer
  """
  def start_link(opts) do
    name =
      opts
      |> Keyword.get(:name)
      |> Finitomata.Supervisor.throttler_name()

    opts = Keyword.put_new(opts, :name, name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  @impl Supervisor
  def init(opts) do
    {initial, opts} = Keyword.pop(opts, :initial, [])
    {name, opts} = Keyword.pop!(opts, :name)

    children = [
      {Producer, initial},
      {Consumer, opts}
    ]

    flags = Supervisor.init(children, strategy: :one_for_one)

    {:ok, _pid} =
      Task.start_link(fn ->
        opts =
          opts
          |> Keyword.take(~w|max_demand interval|a)
          |> Keyword.put_new(:to, producer(name))

        name
        |> consumer()
        |> GenStage.sync_subscribe(opts)
      end)

    flags
  end

  @doc """
  Synchronously executes the function, using throttling based on `GenStage`.

  This function has a default timeout `:infinity` because of its nature
    (throttling is supposed to take a while,) but it might be passed as the third
    argument in a call to `call/3`.

  If a list of functions is given, executes all of them in parallel,
    collects the results, and then returns them to the caller.

  The function might be given as `t:Finitomata.Throttler.t/0` or
    in a simplified form as `{function_of_arity_1, arg}` or `{mod, fun, args}`.
  """
  @spec call(Finitomata.id(), t() | {(any() -> any()), arg} | {module(), atom(), [arg]}) :: any()
        when arg: any()
  def call(name \\ nil, request, timeout \\ :infinity)

  def call(name, requests, timeout) when is_list(requests) do
    requests
    |> Enum.map(&Task.async(Finitomata.Throttler, :call, [name, &1, timeout]))
    |> Task.await_many(timeout)
  end

  @utc_now_truncate_to if(Version.compare(System.version(), "1.15.0") == :lt,
                         do: Calendar.ISO,
                         else: :microsecond
                       )

  def call(name, request, timeout) do
    name
    |> producer()
    |> GenStage.call({:add, request}, timeout)
    |> then(
      &%Finitomata.Throttler{
        &1
        | duration:
            DateTime.diff(DateTime.utc_now(@utc_now_truncate_to), &1.duration, :microsecond)
      }
    )
  end

  @doc false
  def producer(name \\ nil), do: lookup(Producer, name)
  @doc false
  def consumer(name \\ nil), do: lookup(Consumer, name)

  @doc false
  def debug(any, opts \\ []) do
    any
    |> inspect(opts)
    |> Logger.debug()
  end

  defp lookup(who, name) do
    name
    |> Finitomata.Supervisor.throttler_name()
    |> Supervisor.which_children()
    |> Enum.find(&match?({_name, _pid, :worker, [^who]}, &1))
    |> case do
      {_, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end
  end
end
