defmodule FinitomataTest do
  use ExUnit.Case
  doctest Finitomata
  doctest Finitomata.PlantUML
  doctest Finitomata.Mermaid
  doctest Finitomata.Transition

  import ExUnit.CaptureLog

  def setup_all do
  end

  alias Finitomata.Test.P2, as: MyFSM

  test "exported types" do
    defmodule StatesTest do
      @spec foo(MyFSM.state()) :: MyFSM.state()
      def foo(:s1), do: :s1
      def foo(:s2), do: :s2
      def foo(:s3), do: :s3
    end
  end

  test "callbacks" do
    start_supervised(Finitomata.Supervisor)
    Finitomata.start_fsm(MyFSM, "My first FSM", %{foo: :bar})

    assert capture_log(fn ->
             Finitomata.transition("My first FSM", {:to_s2, nil})
             Process.sleep(1_000)
           end) =~
             ~r/\[→ ⇄\].*?\[✓ ⇄\].*?\[← ⇄\]/su

    assert %Finitomata.State{current: :s2, history: [:s1], payload: %{foo: :bar}} =
             Finitomata.state("My first FSM")

    assert Finitomata.allowed?("My first FSM", :*)
    refute Finitomata.responds?("My first FSM", :to_s2)

    assert capture_log(fn ->
             Finitomata.transition("My first FSM", {:__end__, nil})
             Process.sleep(1_000)
           end) =~
             "[◉ ⇄]"
  end
end
