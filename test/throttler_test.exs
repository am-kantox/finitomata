defmodule Finitomata.Throttler.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Throttler
  doctest Finitomata.Throttler.Producer
  doctest Finitomata.Throttler.Consumer

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

    [long, middle, _, _, _, middle_last, short, _, _, _, short_last] =
      throttlers |> Enum.map(& &1.duration) |> Enum.sort() |> Enum.reverse()

    refute_in_delta(long, middle, 100_000)
    refute_in_delta(middle, short, 100_000)
    assert_in_delta(middle, middle_last, 100_000)
    assert_in_delta(short, short_last, 100_000)
  end

  test "Throttling (function)" do
    assert %Finitomata.Throttler{result: 84, payload: :ok} =
             Finitomata.Throttler.call(Throttler, %Finitomata.Throttler{
               fun: &(&1[:value] * 2),
               args: [value: 42],
               payload: :ok
             })
  end
end
