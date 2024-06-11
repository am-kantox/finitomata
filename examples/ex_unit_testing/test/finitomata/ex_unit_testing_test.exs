defmodule ExUnitTesting.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :started ↦ :started ↦ :done ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: ExUnitTesting,
          payload: %{},
          options: [transition_count: 6]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #0", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:retry, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:do, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :done ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: ExUnitTesting,
          payload: %{},
          options: [transition_count: 5]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #1", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:do, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end
end
