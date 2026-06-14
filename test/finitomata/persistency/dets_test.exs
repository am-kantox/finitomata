defmodule Finitomata.Persistency.DETSTest do
  use ExUnit.Case, async: false

  alias Finitomata.Persistency.DETS
  alias Finitomata.Test.{PersistedData, PersistedDETS}

  @id Finitomata.Persistency.DETSTest.Tree

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "finitomata_dets_test_#{System.unique_integer([:positive])}.dets"
      )

    Application.put_env(:finitomata, DETS, file: path)

    on_exit(fn ->
      Application.delete_env(:finitomata, DETS)
      File.rm(path)
    end)

    start_supervised!(DETS)
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "writes snapshots to disk for an FSM" do
    name = "dets-store"
    Finitomata.start_fsm(@id, PersistedDETS, name, %PersistedData{value: 0})
    Process.sleep(100)

    assert {:idle, %PersistedData{value: 0}} = DETS.get(name)

    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    assert {:counted, %PersistedData{value: 1}} = DETS.get(name)
  end

  test "reloads the persisted state after the FSM is restarted by its supervisor" do
    name = "dets-reload"
    Finitomata.start_fsm(@id, PersistedDETS, name, %PersistedData{value: 0})
    Process.sleep(100)
    Finitomata.transition(@id, name, {:bump, nil})
    Finitomata.transition(@id, name, {:bump, nil})
    Process.sleep(100)
    assert {:counted, %PersistedData{value: 2}} = DETS.get(name)

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

  test "snapshots survive the owner (node) restart because they live on disk" do
    name = "dets-durable"
    assert :ok = DETS.store(name, %PersistedData{value: 7}, %{to: :counted})
    assert :ok = DETS.sync()

    # closing and reopening the dets file mimics a node restart
    stop_supervised!(DETS)
    start_supervised!(DETS)

    assert {:counted, %PersistedData{value: 7}} = DETS.get(name)
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
