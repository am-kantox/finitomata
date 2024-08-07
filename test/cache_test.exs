defmodule Finitomata.Cache.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Cache

  import Mox

  @count 25

  setup do
    start_supervised!({Finitomata.Cache, id: CacheLive, type: Finitomata, live?: true, ttl: 100})
    start_supervised!({Finitomata.Cache, id: CacheDead, type: Finitomata, live?: false, ttl: 100})

    parent = self()

    _mox =
      1..@count
      |> Enum.flat_map(
        &[
          {:via, Registry, {Finitomata.CacheLive.Registry, "var_live_#{&1}"}},
          {:via, Registry, {Finitomata.CacheDead.Registry, "var_dead_#{&1}"}}
        ]
      )
      |> Enum.reduce(Finitomata.Cache.Value.Mox, fn fsm_name, mox ->
        allow(mox, parent, fn -> GenServer.whereis(fsm_name) end)
      end)
      |> stub(:after_transition, fn _, _, _ -> :ok end)

    :ok
  end

  test "Caches as expected" do
    Enum.each(1..@count, fn i ->
      assert {:created, ^i} =
               Finitomata.Cache.get(CacheLive, "var_live_#{i}", getter: fn -> i end)

      assert {:created, ^i} =
               Finitomata.Cache.get(CacheDead, "var_dead_#{i}", getter: fn -> i end)
    end)

    Process.sleep(1_000)

    Enum.each(1..@count, fn i ->
      assert {%DateTime{}, ^i} = Finitomata.Cache.get(CacheLive, "var_live_#{i}")
      assert {:instant, ^i} = Finitomata.Cache.get(CacheDead, "var_dead_#{i}")
    end)
  end
end
