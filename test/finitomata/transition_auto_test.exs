defmodule Finitomata.Test.Transition.Test do
  use ExUnit.Case
  import Finitomata.ExUnit
  import Mox

  @moduletag :finitomata

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :accepted ↦ :rejected ↦ :started ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 10]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #0", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :accepted ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 8]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #1", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :accepted ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 7]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #2", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :rejected ↦ :started ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 9]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #3", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 7]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #4", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :accepted ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 6]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #5", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :rejected ↦ :started ↦ :accepted ↦ :accepted ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 10]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #6", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :rejected ↦ :started ↦ :accepted ↦ :accepted ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 9]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #7", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :rejected ↦ :started ↦ :accepted ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 9]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #8", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :rejected ↦ :started ↦ :accepted ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 8]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #9", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:restart, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:accept, nil} ->
        assert_state :accepted do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end

  describe "↝‹:* ↦ :idle ↦ :started ↦ :rejected ↦ :done ↦ :ended ↦ :*›" do
    setup_finitomata do
      # *************************************
      # **** PUT THE INITIALIZATION HERE ****
      # *************************************

      # **** context example:
      parent = self()

      [
        fsm: [
          implementation: Finitomata.Test.Transition,
          payload: %{},
          options: [transition_count: 6]
        ],
        context: [parent: parent]
      ]
    end

    test_path "path #10", %{parent: _parent} = _ctx do
      {:start, nil} ->
        assert_state :started do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:reject, nil} ->
        assert_state :rejected do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

      {:end, nil} ->
        assert_state :done do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end

        assert_state :ended do
          assert_payload do
            # baz ~> ^parent
          end
        end

      {:__end__, nil} ->
        assert_state :* do
          assert_payload do
            # foo.bar.baz ~> ^parent
          end
        end
    end
  end
end
