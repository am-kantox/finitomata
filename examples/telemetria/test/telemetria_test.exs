defmodule FinitomataWithTelemetria.Test do
  use ExUnit.Case
  import ExUnit.CaptureLog

  doctest FinitomataWithTelemetria

  setup_all do
    Application.put_env(:logger, :console, [], persistent: true)
    {:ok, pid} = start_supervised(Finitomata)

    [pid: pid]
  end

  test "sends telemetria events" do
    log =
      capture_log(fn ->
        assert {:ok, _pid} = Finitomata.start_fsm(FinitomataWithTelemetria, "FwT", %{})
        Process.sleep(100)
      end)

    assert log =~ "event: [:finitomata_with_telemetria, :safe_on_transition]"

    {:ok, log} =
      with_log(fn ->
        Finitomata.transition("FwT", :work)
        Process.sleep(1_000)
      end)

    assert log =~ "arg_1: :start"
    assert log =~ "arg_1: :working"
    assert log =~ "arg_1: :done"
  end
end
