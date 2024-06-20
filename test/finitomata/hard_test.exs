defmodule Finitomata.Test.Hard.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :ready ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Hard,
          payload: %{},
          options: [transition_count: 5]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #4", %{finitomata: %{}, parent: _} = _ctx do
      :* ->
        # these validations are not yet handled by `Finitomata.ExUnit`
        # pattern match directly in the context above as shown below to validate
        #
        # %{finitomata: %{auto_init_msgs: %{idle: :foo, started: :bar}}} = _ctx
        assert_state(:idle)

      {:start, nil} ->
        assert_state :ready do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :done do
          assert_payload do
            # baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

        assert_state :* do
          assert_payload do
            # baz ~> ^parent
          end
        end
    end
  end
end
