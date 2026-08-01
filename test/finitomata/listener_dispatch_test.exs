defmodule Finitomata.ListenerDispatchTest do
  @moduledoc """
  A `listener:` may be a `Finitomata.Listener` module or a `GenServer.name()` to send to, and
    the two are told apart by asking whether the atom exports `after_transition/3`.

  That question has a third answer: a module that is perfectly fine but has not been loaded
    yet reports no exports at all. Taking that for a process name and `send/2`-ing to it
    raises, and the raise happens inside the transition, so the _FSM_ dies with it — for a
    listener declared in the usual way, on the very first transition of the run.
  """
  # Unloads a module, so it must not run alongside anything using it.
  use ExUnit.Case, async: false

  alias Finitomata.Test.ColdListener

  @fsm_id ColdListenerDispatch

  setup do
    Process.register(self(), ColdListener.probe())
    :ok
  end

  test "a listener module that has not been loaded yet is still dispatched as a module" do
    unload(ColdListener)

    refute function_exported?(ColdListener, :after_transition, 3),
           "the module was expected to be unloaded, so the test is not exercising anything"

    start_supervised!({Finitomata.Supervisor, id: @fsm_id})

    {:ok, pid} = Finitomata.start_fsm(@fsm_id, Finitomata.Test.Cold, "cold", %{})

    # `start!` is a hard event, so the FSM settles in `:started` on its own. Both the
    # notification and the FSM being alive would be lost if the listener were mistaken for a
    # process name.
    assert_receive {:cold_listener, :started}, Finitomata.ExUnit.assert_receive_timeout()
    assert Process.alive?(pid)

    Finitomata.transition(@fsm_id, "cold", :do)
    assert_receive {:cold_listener, :done}, Finitomata.ExUnit.assert_receive_timeout()
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
  end
end
