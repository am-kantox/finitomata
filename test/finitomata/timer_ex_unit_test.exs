defmodule Finitomata.Test.TimerExUnit.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  @moduletag :finitomata

  describe "↝‹:* ↦ :idle ↦ :processing ↦ :finished ↦ :*›" do
    setup_finitomata do
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.TimerExUnit,
          payload: %{pid: parent},
          options: [transition_count: 4]
        ],
        context: [parent: parent, ex_unit_debug: true]
      ]
    end

    test_path "path #0", %{finitomata: %{}, parent: parent} = _ctx do
      :* ->
        assert_state(:idle)

      :_ ->
        assert_state :processing do
          assert_receive {:on_transition, _, :processing, %{pid: ^parent}}
        end

      :_ ->
        assert_state :processing do
          assert_payload %{processing: true}
        end

      :finish ->
        assert_state :finished do
          assert_payload %{processing: true}
        end

      {:__end__, nil} ->
        assert_state :*
    end
  end
end
