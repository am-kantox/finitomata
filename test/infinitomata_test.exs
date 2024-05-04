defmodule Infinitomata.Test do
  use ExUnit.Case, async: true

  @moduletag :distributed

  setup do
    {_peers, _nodes} = Enfiladex.start_peers(3)
    # Enfiladex.block_call_everywhere(Infinitomata, :start_link, [InfiniTest])
    Infinitomata.start_link(InfiniTest)
    # on_exit(fn -> Enfiladex.stop_peers(peers) end)
    Enfiladex.call_everywhere(Infinitomata, :start_link, [InfiniTest])
    Process.sleep(1000)
    :ok
  end

  test "many instances (distributed)" do
    for i <- 1..10 do
      Infinitomata.start_fsm(InfiniTest, "FSM_#{i}", Finitomata.Test.Log, %{instance: i})
    end

    assert Infinitomata.count(InfiniTest) == 10

    for i <- 1..10 do
      Infinitomata.transition(InfiniTest, "FSM_#{i}", :accept)
    end

    assert %{"FSM_1" => %{}} = Infinitomata.all(InfiniTest)

    for i <- 1..10 do
      Infinitomata.transition(InfiniTest, "FSM_#{i}", :__end__)
    end

    Process.sleep(1_000)

    assert Infinitomata.count(InfiniTest) == 0
    assert Infinitomata.all(InfiniTest) == %{}
  end
end
