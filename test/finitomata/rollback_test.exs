defmodule Finitomata.RollbackTest do
  use ExUnit.Case, async: false

  alias Finitomata.ExUnit.Listener

  defmodule RBFSM do
    @moduledoc false
    @fsm """
    idle --> |go| busy
    busy --> |finish| done
    """
    use Finitomata,
      fsm: @fsm,
      auto_terminate: true,
      impl_for: :on_transition,
      listener: Finitomata.ExUnit.Listener

    @impl Finitomata
    # resolves to `:done`, which is NOT reachable from `:idle` (only `:busy` is) -> rollback
    def on_transition(:idle, :go, %{pid: pid}, state) do
      send(pid, :on_transition_ran)
      {:ok, :done, Map.put(state, :side_effect, true)}
    end

    @impl Finitomata
    def on_rollback(event, _event_payload, %Finitomata.State{} = state) do
      send(state.payload.pid, {:on_rollback, event, state.current, state.last_error})
      :ok
    end

    @impl Finitomata
    def on_failure(event, _event_payload, %Finitomata.State{} = state) do
      send(state.payload.pid, {:on_failure, event, state.current})
      :ok
    end
  end

  @id Finitomata.RollbackTest.Tree

  setup do
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "rolls back when on_transition resolves to a state not allowed from the current one" do
    name = "RB"
    fsm_name = Finitomata.fqn(@id, name)

    Finitomata.start_fsm(@id, RBFSM, name, %{pid: self()})
    # let the entry transition settle *before* registering, so the listener notification
    #   for `:* -> :idle` is not delivered to this test process
    Process.sleep(50)
    Listener.register(fsm_name)

    assert %Finitomata.State{current: :idle} = Finitomata.state(@id, name, :full)

    Finitomata.transition(@id, name, {:go, %{pid: self()}})

    # the business logic of `on_transition/4` ran (its side effects happened) ...
    assert_receive :on_transition_ran, 500

    # ... `on_rollback/3` is invoked with the rejected target carried in `last_error` ...
    assert_receive {:on_rollback, :go, :idle,
                    %Finitomata.Error{stage: :not_allowed, reason: {:not_allowed, :idle, :done}}},
                   500

    # ... `on_failure/3` is still invoked afterwards ...
    assert_receive {:on_failure, :go, :idle}, 500

    # ... and the listener is NOT notified about the rejected transition
    refute_receive {:on_transition, ^fsm_name, _state, _payload}, 200

    # the FSM stayed in `:idle` and recorded the error
    assert %Finitomata.State{
             current: :idle,
             last_error: %Finitomata.Error{
               stage: :not_allowed,
               reason: {:not_allowed, :idle, :done}
             }
           } = Finitomata.state(@id, name, :full)
  end
end
