defmodule Finitomata.Test.WithMocks.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  describe "↝‹:* ↦ :idle ↦ :processed ↦ :*›" do
    setup_finitomata do
      expect(Finitomata.Test.WithMocks.ExtBehaviour.Mox, :void, fn term -> term end)

      [
        fsm: [
          implementation: Finitomata.Test.WithMocks,
          payload: %{},
          options: [transition_count: 3]
        ],
        mocks: [Finitomata.Test.WithMocks.ExtBehaviour.Mox],
        context: [ex_unit_debug: true]
      ]
    end

    test_path "path #0", %{finitomata: %{}} = _ctx do
      :* ->
        # these validations allow `assert_payload/2` calls only
        #
        # also one might pattern match to entry events with payloads directly
        # %{finitomata: %{auto_init_msgs: [idle: :foo, started: :bar]} = _ctx
        assert_state(:idle)

      {:process, nil} ->
        assert_state :processed do
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
