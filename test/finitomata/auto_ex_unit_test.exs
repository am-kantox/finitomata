defmodule Finitomata.Test.AutoExUnit.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :started ↦ :done ↦ :exited ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.AutoExUnit,
          payload: %{},
          options: [transition_count: 5]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #0", %{finitomata: %{}, parent: _} = _ctx do
      :* ->
        # these validations are not yet handled by `Finitomata.ExUnit`
        # pattern match directly in the context above as shown below to validate
        #
        # %{finitomata: %{auto_init_msgs: %{idle: :foo, started: :bar}}} = _ctx
        assert_state(:idle)
        assert_state(:started)
        assert_state(:done)

      {:exit, nil} ->
        assert_state :exited do
          assert_payload do
            # foo.bar.baz ~> ^parent
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
