defmodule FinitomataWithTelemetria do
  @moduledoc """
  Demonstration of `Telemetria` integration for `Finitomata`.
  """

  @fsm """
    start --> |work| working
    working --> |shutdown!| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  @impl Finitomata
  def on_transition(:start, :work, _event_payload, state_payload),
    do: {:ok, :working, state_payload}

  def on_transition(:working, :shutdown!, _event_payload, state_payload),
    do: {:ok, :done, state_payload}
end
