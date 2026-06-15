defmodule Finitomata.ForkFailureTest do
  use ExUnit.Case, async: false

  alias Finitomata.ExUnit.Listener

  defmodule Sub do
    @moduledoc false
    # a placeholder fork target; it is never started because the resolution fails
  end

  defmodule ForkFailFSM do
    @moduledoc false
    @fsm """
    idle --> |go| forking
    forking --> |proceed| done
    """
    use Finitomata,
      fsm: @fsm,
      forks: [forking: [proceed: Finitomata.ForkFailureTest.Sub]],
      impl_for: :on_transition,
      listener: Finitomata.ExUnit.Listener

    @impl Finitomata
    def on_transition(:idle, :go, _payload, state), do: {:ok, :forking, state}

    @impl Finitomata
    # resolves to a module that is NOT among the configured forks -> `:unknown_fork_resolution`
    def on_fork(:forking, _state_payload), do: {:ok, __MODULE__}
  end

  @id Finitomata.ForkFailureTest.Tree

  setup do
    start_supervised!({Finitomata.Supervisor, id: @id})
    :ok
  end

  test "notifies the listener when on_fork/2 resolution fails" do
    name = "FF"
    fsm_name = Finitomata.fqn(@id, name)

    Finitomata.start_fsm(@id, ForkFailFSM, name, %{})
    # register after the entry transition has settled
    Process.sleep(50)
    Listener.register(fsm_name)

    Finitomata.transition(@id, name, :go)

    assert_receive {:on_fork_failure, ^fsm_name, :forking, :unknown_fork_resolution}, 500

    # the FSM stays in the fork state, it did not crash
    assert %Finitomata.State{current: :forking} = Finitomata.state(@id, name, :full)
  end
end
