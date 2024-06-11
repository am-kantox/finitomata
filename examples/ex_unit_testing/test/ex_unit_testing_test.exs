defmodule ExUnitTesting.CustomTest do
  use ExUnit.Case, async: true
  doctest ExUnitTesting

  import Finitomata.ExUnit
  import Mox

  alias ExUnitTesting, as: Ca

  describe "Ca FSM tests" do
    setup_finitomata do
      parent = self()

      [
        fsm: [
          id: Case,
          implementation: Ca,
          payload: Ca.cast!(%{internals: %{counter: 0}})
        ],
        context: [
          parent: parent
        ]
      ]
    end

    test_path "The only path", %{finitomata: %{test_pid: parent}} do
      {:start, self()} ->
        assert_state :started do
          assert_payload do
            internals.counter ~> 1
            pid ~> ^parent
          end
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
