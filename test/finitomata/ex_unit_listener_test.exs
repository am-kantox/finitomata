defmodule Finitomata.ExUnit.ListenerTest do
  use ExUnit.Case, async: false

  # NB: no `import Mox` — the FSM uses `listener: Finitomata.ExUnit.Listener`.
  import Finitomata.ExUnit

  alias Finitomata.Test.ListenerExUnit, as: FLE

  describe "Mox-free listener" do
    setup_finitomata do
      [
        fsm: [
          id: MoxFreeCase,
          implementation: FLE,
          payload: FLE.cast!(%{internals: %{counter: 0}})
        ]
      ]
    end

    test_path "drives the whole path without Mox", _ctx do
      :start ->
        assert_state :started do
          assert_payload do: internals.counter ~> 1
        end

      :do ->
        assert_state :done
        assert_state :*
    end

    test "assert_no_transition exposes the error of a failed transition", ctx do
      assert_transition ctx, :start do
        :started ->
          assert_payload do: internals.counter ~> 1
      end

      assert_no_transition ctx, :reject? do
        assert %Finitomata.Error{reason: :rejected} = last_error
        assert :started = state.current
      end
    end
  end

  test "event_generator/1 yields only externally-triggerable events" do
    events = FLE.__config__(:events)
    sample = FLE |> Finitomata.ExUnit.event_generator() |> Enum.take(25)

    assert Enum.all?(sample, &(&1 in events))
    refute Enum.any?(sample, &(&1 in [:__start__, :__end__]))
  end
end
