defmodule Finitomata.StateCacheTest do
  use ExUnit.Case, async: false

  alias Finitomata.Test.Log

  @id Finitomata.StateCacheTest.Tree

  setup do
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "caches the payload while the FSM is alive and clears it on termination" do
    Finitomata.start_fsm(@id, Log, "Cached", %{foo: :bar})
    Process.sleep(100)

    # written by the entry transition / `state/3` and readable without a call
    assert %{foo: :bar} = Finitomata.state(@id, "Cached", :cached)
    assert %{foo: :bar} = Finitomata.state(@id, "Cached", :payload)

    Finitomata.transition(@id, "Cached", {:accept, nil})
    Process.sleep(100)

    assert %Finitomata.State{current: :accepted, payload: %{foo: :bar}} =
             Finitomata.state(@id, "Cached", :full)

    assert %{foo: :bar} = Finitomata.state(@id, "Cached", :cached)

    Finitomata.transition(@id, "Cached", {:__end__, nil})
    Process.sleep(200)

    refute Finitomata.alive?(@id, "Cached")
    # the cache entry is removed on `terminate/2` rather than lingering forever
    assert is_nil(Finitomata.state(@id, "Cached", :cached))
  end

  test "the ETS-backed cache owns a named table per supervision tree" do
    if Finitomata.StateCache.backend() == :ets do
      table = Finitomata.StateCache.name(@id)
      assert :undefined != :ets.whereis(table)
    end
  end

  test "reading the cache for an unknown tree is safe and returns the default" do
    assert is_nil(Finitomata.StateCache.get(:no_such_tree, "nope"))
    assert :default == Finitomata.StateCache.get(:no_such_tree, "nope", :default)
  end
end
