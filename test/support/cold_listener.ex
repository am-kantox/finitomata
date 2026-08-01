defmodule Finitomata.Test.ColdListener do
  @moduledoc false

  # Used by one test only, which unloads this module to reproduce a listener that has not
  #   been reached yet. Nothing else may depend on it being loaded.

  @behaviour Finitomata.Listener

  @probe :finitomata_cold_listener_probe

  @doc false
  def probe, do: @probe

  @impl Finitomata.Listener
  def after_transition(_id, state, _payload) do
    case Process.whereis(@probe) do
      nil -> :ok
      pid -> send(pid, {:cold_listener, state})
    end

    :ok
  end
end

defmodule Finitomata.Test.Cold do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |do| done
  """

  use Finitomata, fsm: @fsm, listener: Finitomata.Test.ColdListener
end
