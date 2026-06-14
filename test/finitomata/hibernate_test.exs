defmodule Finitomata.HibernateTest do
  use ExUnit.Case, async: false

  defmodule HibFSM do
    @moduledoc false
    @fsm """
    idle --> |go| busy
    busy --> |finish| done
    """
    use Finitomata, fsm: @fsm, auto_terminate: true, hibernate: true

    @impl Finitomata
    def on_transition(:idle, :go, _payload, state),
      do: {:ok, :busy, Map.put(state, :went, true)}

    def on_transition(:busy, :finish, _payload, state),
      do: {:ok, :done, state}
  end

  @id Finitomata.HibernateTest.Tree

  setup do
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "transitions, state queries and the cache work with hibernate: true" do
    Finitomata.start_fsm(@id, HibFSM, "H", %{})
    Process.sleep(50)

    assert %Finitomata.State{current: :idle, hibernate: true} =
             Finitomata.state(@id, "H", :full)

    Finitomata.transition(@id, "H", :go)
    Process.sleep(50)

    assert %Finitomata.State{current: :busy, payload: %{went: true}} =
             Finitomata.state(@id, "H", :full)

    assert %{went: true} = Finitomata.state(@id, "H", :cached)

    # busy --> done, then auto_terminate fires __end__ and the FSM stops
    Finitomata.transition(@id, "H", :finish)
    Process.sleep(150)
    refute Finitomata.alive?(@id, "H")
  end
end
