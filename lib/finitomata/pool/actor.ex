defmodule Finitomata.Pool.Actor do
  @moduledoc """
  The behaviour specifying the actor in the pool.
  """

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`,
    see `t:Finitomata.Pool.responsive_actor/0`
  """
  @callback actor(term(), Finitomata.State.payload()) :: {:ok, term()} | {:error, any()}

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`
    after `actor/2` returned successfully with a result of invocation
    and the state of the `Pool` worker,
    see `t:Finitomata.Pool.naive_handler/0`.

  The value returned from this call will be send as an last argument 
    of the message to the caller of `Finitomata.Pool.run/3` if the `pid`
    was passed.
  """
  @callback on_result(term()) :: any()

  @doc """
  The function which would be invoked in `Finitomata.Pool.run/3`
    after `actor/2` failed with a failure message and the state
    of the `Pool` worker,
    see `t:Finitomata.Pool.naive_handler/0`.

  The value returned from this call will be send as an last argument 
    of the message to the caller of `Finitomata.Pool.run/3` if the `pid`
    was passed.
  """
  @callback on_error(term()) :: any()

  @optional_callbacks on_result: 1, on_error: 1
end
