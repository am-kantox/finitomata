defmodule Finitomata.Test.Determined.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  @moduletag :finitomata

  describe "↝‹:* ↦ :idle ↦ :started ↦ :step1 ↦ :step2 ↦ :step3 ↦ :done ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Determined,
          payload: %{},
          options: [transition_count: 7]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #0", %{finitomata: %{}, parent: _} = _ctx do
      :* ->
        # these validations allow `assert_payload/2` calls only
        #
        # also one might pattern match to entry events with payloads directly
        # %{finitomata: %{auto_init_msgs: [idle: :foo, started: :bar]} = _ctx
        assert_state(:idle)

        assert_state :started do
          assert_payload %{}
        end

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
          assert_payload %{step: 2}
        end

        assert_state :done do
          assert_payload %{step: 2}
        end

        assert_state :* do
          assert_payload do
            step ~> 2
          end
        end
    end
  end
end
