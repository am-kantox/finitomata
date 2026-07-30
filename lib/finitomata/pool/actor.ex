defmodule Finitomata.Pool.Actor do
  @moduledoc """
  The behaviour specifying the actor in the pool.
  """

  alias Finitomata.{Pool, State}

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`,
    see `t:Finitomata.Pool.responsive_actor/0`
  """
  @callback actor(term(), State.payload()) :: {:ok, term()} | {:error, any()}

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`
    after `actor/2` returned successfully with a result of invocation
    and the state of the `Pool` worker,
    see `t:Finitomata.Pool.naive_handler/0`.

  The value returned from this call will be send as an last argument 
    of the message to the caller of `Finitomata.Pool.run/3` if the `pid`
    was passed.
  """
  @callback on_result(result :: term(), id :: Pool.id()) :: any()

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`
    after `actor/2` failed with a failure message and the state
    of the `Pool` worker,
    see `t:Finitomata.Pool.naive_handler/0`.

  The value returned from this call will be send as an last argument 
    of the message to the caller of `Finitomata.Pool.run/3` if the `pid`
    was passed.
  """
  @callback on_error(error :: term(), id :: Pool.id()) :: any()

  @optional_callbacks on_result: 2, on_error: 2

  if Code.ensure_loaded?(StreamData) do
    @doc """
    `StreamData` helper to produce `on_error/2` and `on_result/2` handlers
    """
    def handler, do: handler(:result)
    def handler(:error), do: do_handler(error: true)
    def handler(:result), do: do_handler(error: false)
    def handler(f) when is_function(f, 2), do: do_handler(handler: f)

    defp do_handler(options) when is_list(options) do
      default = fn ->
        if Keyword.get(options, :error, false),
          do: &__MODULE__.error_logger/2,
          else: &__MODULE__.result_logger/2
      end

      handler = Keyword.get_lazy(options, :handler, default)
      StreamData.constant(handler)
    end
  end

  @doc false
  def result_logger(result, id) do
    require Logger
    Logger.info("[👷] Pool worker: ‹#{inspect(id)}› succeeded: ‹#{inspect(result)}›")
  end

  @doc false
  def error_logger(error, id) do
    require Logger
    Logger.warning("[👷] Pool worker: ‹#{inspect(id)}› errored: ‹#{inspect(error)}›")
  end
end
