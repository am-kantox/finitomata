defmodule Finitomata.Finitomata.MyFSM.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  @moduletag :finitomata

  describe "↝‹:* ↦ :idle ↦ :started ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Finitomata.MyFSM,
          payload: %{parent: parent},
          options: [transition_count: 3]
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

      {:start, nil} ->
        assert_state :started do
          # assert_payload %{foo: :bar}
        end

        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end
end
