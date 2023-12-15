defmodule Finitomata.Test do
  use ExUnit.Case

  doctest Finitomata
  doctest Finitomata.PlantUML
  doctest Finitomata.Mermaid

  import ExUnit.CaptureLog

  use ExUnitProperties

  alias Finitomata.Test.{Auto, Callback, EnsureEntry, ErrorAttach, Log, Soft, Timer}

  test "exported types" do
    defmodule StatesTest do
      @spec foo(Log.state()) :: Log.state()
      def foo(:s1), do: :s1
      def foo(:s2), do: :s2
      def foo(:s3), do: :s3
    end
  end

  test "callbacks (log)" do
    start_supervised({Finitomata.Supervisor, id: LogFSM})

    Finitomata.start_fsm(LogFSM, Log, "LogFSM", %{foo: :bar})

    assert capture_log(fn ->
             Finitomata.transition(LogFSM, "LogFSM", {:accept, nil})
             Process.sleep(200)
           end) =~
             ~r/\[→ ↹\].*?\[✓ ⇄\].*?\[← ↹\]/su

    assert %{foo: :bar} = Finitomata.state(LogFSM, "LogFSM", :payload)

    assert %Finitomata.State{current: :accepted, history: [:idle, :*], payload: %{foo: :bar}} =
             Finitomata.state(LogFSM, "LogFSM")

    assert Finitomata.allowed?(LogFSM, "LogFSM", :*)
    refute Finitomata.responds?(LogFSM, "LogFSM", :accept)

    assert capture_log(fn ->
             Finitomata.transition(LogFSM, "LogFSM", {:__end__, nil})
             Process.sleep(200)
           end) =~
             "[◉ ↹]"

    Finitomata.transition(LogFSM, "LogFSM", {:__end__, nil})
    Process.sleep(200)
    refute Finitomata.alive?(LogFSM, "LogFSM")
  end

  test "callbacks (callback)" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Callback, :callback, %{})
    Finitomata.transition(:callback, {:process, %{pid: pid}})

    assert_receive :on_transition

    assert %{pid: ^pid} = Finitomata.state(:callback, :full).payload
    assert %{pid: ^pid} = Finitomata.state(:callback, :cached)

    assert %Finitomata.State{current: :processed, history: [:idle, :*], payload: %{pid: ^pid}} =
             Finitomata.state(:callback, :full)

    assert Finitomata.allowed?(:callback, :*)
    refute Finitomata.responds?(:callback, :process)

    Finitomata.transition(:callback, {:__end__, nil})
    Process.sleep(200)
    refute Finitomata.alive?(:callback)
  end

  test "callbacks (callback, deferred)" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Callback, :callback, %{})
    Finitomata.transition(:callback, {:process, %{pid: pid}}, 800)

    refute_receive :on_transition, 500
    assert_receive :on_transition, 500
  end

  test "timer" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(:timer, Timer, %{pid: pid})
    assert_receive :on_transition, 500
    assert_receive :on_timer, 500
    assert_receive :on_timer, 500

    assert %{pid: ^pid, processing: true} = Finitomata.state(:timer, :payload)
  end

  test "malformed timer definition" do
    ast =
      quote do
        @fsm """
        idle --> |process| processed
        """
        use Finitomata, fsm: @fsm, timer: 100, impl_for: :on_transition
      end

    assert_raise CompileError, fn ->
      Module.create(Finitomata.Test.MalformedTimer, ast, __ENV__)
    end
  end

  test "auto" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Auto, :auto, %{pid: pid})

    assert_receive :on_start!, 500
    assert_receive :on_do!, 500
    assert_receive :on_end, 500

    Process.sleep(200)
    refute Finitomata.alive?(:auto)
  end

  test "ensure entry" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(EnsureEntry, :ee, %{pid: pid})

    assert_receive :retrying_1, 500
    assert_receive :retrying_2, 500
    assert_receive :exhausted, 500
    assert_receive :on_process!, 500

    Process.sleep(200)
    refute Finitomata.alive?(:ee)
  end

  test "soft" do
    start_supervised(Finitomata.Supervisor)

    Finitomata.start_fsm(Soft, "SoftFSM", %{foo: :bar})

    assert capture_log(fn ->
             Finitomata.transition("SoftFSM", {:do?, nil})
             Process.sleep(200)
           end) =~ "[⚐ ↹] transition softly failed {:error, :not_allowed}"

    Process.sleep(200)
    assert %Finitomata.State{current: :started} = Finitomata.state("SoftFSM", :full)
    assert %{foo: :bar} = Finitomata.state("SoftFSM", :cached)

    assert ~s|#Finitomata<[name: "SoftFSM", state: [current: :started, previous: :idle, payload: %{foo: :bar}], | <>
             ~s|internals: [errored?: [not_allowed: | <> _ = inspect(Finitomata.state("SoftFSM"))

    assert Finitomata.alive?("SoftFSM")
  end

  test "error attached" do
    start_supervised(Finitomata.Supervisor)
    fsm = "ErrorFSM"
    Finitomata.start_fsm(ErrorAttach, fsm, %{foo: :bar})

    captured_log =
      capture_log(fn ->
        Finitomata.transition(fsm, {:start, nil})
        Process.sleep(200)
      end)

    assert captured_log =~ "[failure] {:error, \"Test error\"}"
    assert captured_log =~ "[failure] state: :idle"
    assert captured_log =~ "[failure] event: :start"
  end

  test "persistency" do
    start_supervised(Finitomata.Supervisor)
    fsm = "PersistentFSM"

    Finitomata.start_fsm(Finitomata.Test.Persistency, fsm, %Finitomata.Test.Persistency{
      pid: self()
    })

    assert_receive :on_start!
    assert_receive :on_do!
    assert_receive :on_end
  end
end
