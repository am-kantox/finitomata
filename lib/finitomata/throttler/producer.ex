defmodule Finitomata.Throttler.Producer do
  @moduledoc false
  use GenStage

  alias Finitomata.Throttler

  def start_link(initial \\ []),
    do: GenStage.start_link(__MODULE__, initial)

  @spec init([Throttler.throttlee()]) :: {:producer, [Throttler.throttlee()]}
  @impl GenStage
  def init(initial) when is_list(initial),
    do: {:producer, normalize(nil, initial)}

  @impl GenStage
  def handle_demand(demand, items) when demand > 0 do
    {head, tail} = Enum.split(items, demand)
    {:noreply, head, tail}
  end

  @impl GenStage
  def handle_call({:add, items}, from, state) when is_list(items),
    do: {:noreply, [], state ++ normalize(from, items)}

  def handle_call({:add, item}, from, state),
    do: handle_call({:add, [item]}, from, state)

  @utc_now_truncate_to if(Version.compare(System.version(), "1.15.0") == :lt,
                         do: Calendar.ISO,
                         else: :microsecond
                       )

  defp normalize(from, items) do
    Enum.map(items, fn
      %Throttler{} = t ->
        %{t | from: from, duration: DateTime.utc_now(@utc_now_truncate_to)}

      {fun, args} when is_function(fun, 1) ->
        %Throttler{
          from: from,
          fun: fun,
          args: args,
          duration: DateTime.utc_now(@utc_now_truncate_to)
        }

      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        %Throttler{
          from: from,
          fun: {mod, fun},
          args: args,
          duration: DateTime.utc_now(@utc_now_truncate_to)
        }

      fun when is_function(fun, 0) ->
        %Throttler{
          from: from,
          fun: fun,
          args: [],
          duration: DateTime.utc_now(@utc_now_truncate_to)
        }

      value ->
        %Throttler{
          from: from,
          fun: &Throttler.debug/1,
          args: [value: value],
          duration: DateTime.utc_now(@utc_now_truncate_to)
        }
    end)
  end
end
