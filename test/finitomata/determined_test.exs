defmodule Finitomata.Test.Determined.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :started ↦ :step1 ↦ :step2 ↦ :step3 ↦ :done ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Determined,
          payload: %{parent: parent},
          options: [transition_count: 7]
        ],
        context: [ex_unit_debug: true]
      ]
    end

    test_path "path #0", _ctx = %{finitomata: %{}} do
      :* ->
        # these validations are not yet handled by `Finitomata.ExUnit`
        # pattern match directly in the context above as shown below to validate
        #
        # %{finitomata: %{auto_init_msgs: %{idle: :foo, started: :bar}}} = _ctx
        assert_state(:idle)
        assert_state(:started)

        assert_state :step1 do
          assert_payload %{step: 1}
        end

        assert_state :step2 do
          assert_payload do
            step ~> 2
          end
        end

      {:continue, nil} ->
        assert_state :step3 do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :done do
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
