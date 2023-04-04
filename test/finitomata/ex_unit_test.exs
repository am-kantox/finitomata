defmodule Finitomata.ExUnit.Test do
  use ExUnit.Case

  use ExUnitProperties
  import Mox
  import Finitomata.ExUnit

  alias Finitomata.Test.Listener, as: FTL

  test "standard approach" do
    start_supervised(Finitomata.Supervisor)

    check all fini_name <- StreamData.string(:alphanumeric, min_length: 16),
              _fini_payload <-
                StreamData.one_of([StreamData.atom(:alphanumeric), StreamData.integer(1..100)]),
              max_runs: 50 do
      fsm_name = {:via, Registry, {Finitomata.Registry, fini_name}}
      parent = self()

      FTL.Mox
      |> allow(parent, fn -> GenServer.whereis(fsm_name) end)
      |> expect(:after_transition, 4, fn id, state, payload ->
        parent |> send({:on_transition, id, state, payload}) |> then(fn _ -> :ok end)
      end)

      Finitomata.start_fsm(FTL, fini_name, %FTL{})

      assert_receive {:on_transition, ^fsm_name, :idle, %{internals: %{counter: 0}}}

      Finitomata.transition(fini_name, {:start, parent})
      assert_receive {:on_start, ^parent}
      assert_receive {:on_transition, ^fsm_name, :started, %{pid: ^parent}}

      Finitomata.transition(fini_name, :do)
      assert_receive :on_do
      assert_receive {:on_transition, ^fsm_name, :done, %{pid: ^parent}}

      assert_receive :on_end
      assert_receive {:on_transition, ^fsm_name, :*, %{pid: ^parent}}
    end
  end

  describe "custom assertions" do
    setup_finitomata do
      parent = self()

      [
        fsm: [
          id: Case,
          implementation: FTL,
          payload: FTL.cast!(%{internals: %{counter: 0}})
        ],
        context: [
          parent: parent
        ]
      ]
    end

    test "low level with assert_transition", %{finitomata: %{test_pid: parent, fsm: fsm}} do
      assert_transition fsm.id, fsm.implementation, fsm.name, {:start, parent} do
        :started ->
          assert_payload do: internals.counter ~> 1
          assert_receive {:on_start, ^parent}
      end

      assert_transition fsm.id, fsm.implementation, fsm.name, :do do
        :done ->
          assert_payload do
            internals.counter ~> 2
            pid ~> ^parent
          end

          assert_receive :on_do

        :* ->
          assert_receive :on_end
          assert_payload %{internals: %{counter: 2}, pid: ^parent}
      end
    end

    test "higher level with assert_transition", %{finitomata: %{test_pid: parent}} = ctx do
      assert_transition ctx, {:start, parent} do
        :started ->
          assert_payload do: internals.counter ~> 1
          assert_receive {:on_start, ^parent}
      end

      assert_transition ctx, :do do
        :done ->
          assert_payload do
            internals.counter ~> 2
            pid ~> ^parent
          end

          assert_receive :on_do

        :* ->
          assert_receive :on_end
          assert_payload %{internals: %{counter: 2}, pid: ^parent}
      end
    end

    _ = """
    test_path "Test Path Test",
              Case,
              FTL,
              "TestPathAssertionFSM",
              FTL.cast!(%{internals: %{counter: 0}, pid: self()}),
              parent: self() do
    """

    test_path "The only path", %{finitomata: %{test_pid: parent}} do
      {:start, self()} ->
        assert_state :started do
          assert_payload do
            internals.counter ~> 1
            pid ~> ^parent
          end

          assert_receive {:on_start, ^parent}
        end

      :do ->
        assert_state :done do
          assert_receive :on_do
        end

        assert_state :* do
          assert_receive :on_end
        end
    end
  end
end
