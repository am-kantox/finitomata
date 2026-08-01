defmodule Finitomata.ExUnitPersistencyTest do
  @moduledoc """
  `setup_finitomata/1` against an _FSM_ declaring `persistency:`.

  Such an _FSM_ breaks both assumptions the plain setup makes: the payload it carries is the
    one `c:Finitomata.Persistency.load/1` returned rather than the one the test passed, and a
    `:loaded` lifecycle skips the entry transition, so there is no entry notification to wait
    for. Before those were accounted for, the setup of every test below timed out.
  """
  use ExUnit.Case, async: true

  import Finitomata.ExUnit

  alias Finitomata.Test.PersistedPayload

  describe "an FSM resumed from storage" do
    setup_finitomata do
      [
        fsm: [
          implementation: Finitomata.Test.PersistedListener,
          payload: %PersistedPayload{resume_at: :started, value: 41}
        ]
      ]
    end

    test_path "resumes where storage left it, carrying the loaded payload" do
      :* ->
        assert_state :started do
          # 41 going in, 42 coming out: the payload belongs to the persistency, and
          # asserting it here is only possible because the setup stopped pinning
          # the one the test passed.
          assert_payload(%{value: 42})
        end

      {:do, nil} ->
        assert_state(:done)
    end
  end

  describe "an FSM with nothing to resume" do
    setup_finitomata do
      [
        fsm: [
          implementation: Finitomata.Test.PersistedListener,
          payload: %PersistedPayload{resume_at: nil, value: 7}
        ]
      ]
    end

    test_path "runs the entry transition as it would without a persistency" do
      :* ->
        assert_state(:idle)

        assert_state :started do
          # 8, not the 7 that went in: even when the entry transition does run, the
          # payload is the loaded one.
          assert_payload(%{value: 8})
        end

      {:do, nil} ->
        assert_state(:done)
    end
  end
end
