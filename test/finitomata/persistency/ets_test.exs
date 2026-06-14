defmodule Finitomata.Persistency.ETSTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Finitomata.Persistency.ETS
  alias Finitomata.Test.{PersistedData, PersistedETS}

  @id Finitomata.Persistency.ETSTest.Tree

  setup do
    start_supervised!(ETS)
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "writes a snapshot for the entry transition and each successful transition" do
    name = "ets-store"
    Finitomata.start_fsm(@id, PersistedETS, name, %PersistedData{value: 0})
    Process.sleep(100)

    # the freshly created entity is persisted by the entry transition
    assert {:idle, %PersistedData{value: 0}} = ETS.get(name)

    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    assert {:counted, %PersistedData{value: 1}} = ETS.get(name)

    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    assert {:counted, %PersistedData{value: 2}} = ETS.get(name)
  end

  test "persists transition failures through store_error/4 without losing the snapshot" do
    name = "ets-error"
    Finitomata.start_fsm(@id, PersistedETS, name, %PersistedData{value: 0})
    Process.sleep(100)
    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)

    assert is_nil(ETS.last_error(name))

    capture_log(fn ->
      Finitomata.transition(@id, name, {:boom, nil})
      Process.sleep(100)
    end)

    assert %{reason: :boom, payload: %PersistedData{value: 1}} = ETS.last_error(name)
    # the last good snapshot is untouched by the failed transition
    assert {:counted, %PersistedData{value: 1}} = ETS.get(name)
  end

  test "reloads the persisted state after the FSM is restarted by its supervisor" do
    name = "ets-reload"
    Finitomata.start_fsm(@id, PersistedETS, name, %PersistedData{value: 0})
    Process.sleep(100)
    Finitomata.transition(@id, name, {:bump, nil})
    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    assert {:counted, %PersistedData{value: 2}} = ETS.get(name)

    # kill the FSM; the transient child is restarted and must reload from ETS
    pid = @id |> Finitomata.fqn(name) |> GenServer.whereis()
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

    wait_until(fn ->
      match?(
        %Finitomata.State{current: :counted, payload: %PersistedData{value: 2}},
        safe_state(name)
      )
    end)

    assert %Finitomata.State{current: :counted, payload: %PersistedData{value: 2}} =
             Finitomata.state(@id, name, :full)
  end

  test "purge/1 removes the snapshot and any stored error" do
    name = "ets-purge"
    Finitomata.start_fsm(@id, PersistedETS, name, %PersistedData{value: 0})
    Process.sleep(100)
    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    refute is_nil(ETS.get(name))

    assert :ok = ETS.purge(name)
    assert is_nil(ETS.get(name))
  end

  defp safe_state(name) do
    Finitomata.state(@id, name, :full)
  catch
    :exit, _ -> nil
  end

  defp wait_until(fun, retries \\ 100) do
    cond do
      fun.() ->
        :ok

      retries == 0 ->
        :ok

      true ->
        Process.sleep(20)
        wait_until(fun, retries - 1)
    end
  end
end
