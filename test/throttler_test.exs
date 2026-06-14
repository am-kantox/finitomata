defmodule Finitomata.Throttler.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Throttler
  doctest Finitomata.Throttler.Producer
  doctest Finitomata.Throttler.Consumer

  # mirrors the default `interval` of `Finitomata.Throttler.Consumer`
  @interval 400

  setup do
    %{siblings: start_supervised!({Finitomata.Throttler, name: Throttler})}
  end

  test "Throttling" do
    assert %Finitomata.Throttler{
             args: [value: 42],
             result: :ok,
             payload: nil
           } = Finitomata.Throttler.call(Throttler, 42)
  end

  test "Throttling (multiple call)" do
    assert [
             %Finitomata.Throttler{args: [value: 1]},
             %Finitomata.Throttler{args: [value: 2]},
             %Finitomata.Throttler{args: [value: 3]},
             %Finitomata.Throttler{args: [value: 4]},
             %Finitomata.Throttler{args: [value: 5]},
             %Finitomata.Throttler{args: [value: 6]},
             %Finitomata.Throttler{args: [value: 7]},
             %Finitomata.Throttler{args: [value: 8]},
             %Finitomata.Throttler{args: [value: 9]},
             %Finitomata.Throttler{args: [value: 10]},
             %Finitomata.Throttler{args: [value: 11]}
           ] = throttlers = Finitomata.Throttler.call(Throttler, Enum.to_list(1..11))

    # Each call's `duration` is measured from enqueue to completion. Throttling releases
    #   at most `max_demand` (default 5) calls per `@interval`, so for 11 calls the
    #   durations fall into `ceil(11 / 5) == 3` interval-separated batches. Clustering by a
    #   gap of half the interval is far above scheduling jitter yet far below the
    #   inter-batch gap, so this is robust without depending on the exact per-batch
    #   composition (the previous per-index `*_in_delta` assertions were timing-flaky).
    durations = throttlers |> Enum.map(& &1.duration) |> Enum.sort()
    batches = cluster_by_gap(durations, @interval * 500)

    assert [_first, _second, _third] = batches

    # later batches are delayed by at least one whole interval relative to the first
    assert List.last(durations) - hd(durations) > @interval * 1_000
  end

  test "Throttling (function)" do
    assert %Finitomata.Throttler{result: 84, payload: :ok} =
             Finitomata.Throttler.call(Throttler, %Finitomata.Throttler{
               fun: &(&1[:value] * 2),
               args: [value: 42],
               payload: :ok
             })
  end

  # Splits an ascending list of durations into clusters, starting a new cluster
  #   whenever the gap to the previous duration exceeds `gap`.
  defp cluster_by_gap(sorted, gap) do
    Enum.chunk_while(
      sorted,
      [],
      fn duration, acc ->
        case acc do
          [previous | _] when duration - previous > gap ->
            {:cont, Enum.reverse(acc), [duration]}

          _ ->
            {:cont, [duration | acc]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end
end
