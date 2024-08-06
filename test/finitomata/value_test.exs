defmodule Finitomata.Cache.Value.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  alias Finitomata.Cache.Value

  @moduletag :finitomata

  describe "↝‹:* ↦ :idle ↦ :ready ↦ :set ↦ :ready ↦ :done ↦ :*›" do
    setup_finitomata do
      ttl = 1_000
      getter = &DateTime.utc_now/0

      [
        fsm: [
          implementation: Value,
          payload: %{live?: true, ttl: ttl, getter: getter},
          options: [transition_count: 10]
        ],
        context: [ttl: ttl, value: getter.(), getter: getter]
      ]
    end

    test_path "path #0", %{finitomata: %{}, ttl: ttl, getter: getter, value: value} = _ctx do
      :* ->
        assert_state(:idle)

        assert_state :ready do
          assert_payload %Value{ttl: ^ttl, value: :error}
        end

      {:set, {getter, value}} ->
        assert_state :set do
          assert_payload %Value{value: {:ok, ^value}}
        end

        assert_state :ready do
          assert_payload %Value{value: {:ok, ^value}}
        end

      :_ ->
        assert_state :set do
          assert_payload %Value{value: {:ok, new_value}} when new_value != value
        end

        assert_state :ready do
          assert_payload %Value{value: {:ok, new_value}} when new_value != value
        end

      {:stop, nil} ->
        assert_state :done do
          # assert_payload %{foo: :bar}
        end

        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :ready ↦ :done ↦ :*›" do
    setup_finitomata do
      [
        fsm: [
          implementation: Value,
          payload: %Value{live?: true, ttl: 1_000, getter: &DateTime.utc_now/0},
          options: [transition_count: 5]
        ],
        context: []
      ]
    end

    test_path "path #1", %{finitomata: %{}} = _ctx do
      :* ->
        assert_state(:idle)

        assert_state :ready do
          # assert_payload %{}
        end

      {:stop, nil} ->
        assert_state :done do
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
