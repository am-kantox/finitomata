defmodule Finitomata.Test.Sequenced.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [implementation: Finitomata.Test.Sequenced, payload: %{}],
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

        assert_state :accepted do
          assert_payload do
            # baz ~> ^parent
          end
        end

        assert_state :rejected do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end
end
