defmodule InfinitomataTest do
  use ExUnit.Case, async: true

  # alias Finitomata.Test.Listener, as: FTL

  setup do
    {_peers, _nodes} = Enfiladex.start_peers(3)

    [node() | Node.list()] |> Enum.each(&:rpc.block_call(&1, Infinitomata, :start_link, []))

    # on_exit(fn -> Enfiladex.stop_peers(peers) end)
  end

  test "many instances (distributed)" do
    for i <- 1..10 do
      Infinitomata.start_fsm("FSM_#{i}", Finitomata.Test.Log, %{instance: i})
    end

    assert Infinitomata.count(Infinitomata) == 10

    for i <- 1..10 do
      Infinitomata.transition("FSM_#{i}", :accept)
    end

    assert %{"FSM_1" => %{}} = Infinitomata.all(Infinitomata)

    for i <- 1..10 do
      Infinitomata.transition("FSM_#{i}", :__end__)
    end

    Process.sleep(1_000)

    assert Infinitomata.count(Infinitomata) == 0
    assert Infinitomata.all(Infinitomata) == %{}
  end
end
