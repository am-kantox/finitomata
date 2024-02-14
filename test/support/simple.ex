defmodule SimpleFSM do
  @moduledoc false

  @fsm """
  init --> |initialize!| ready
  ready --> |publish| published
  ready --> |publish| ready
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  def on_transition(:ready, :publish, true, state),
    do: {:ok, :published, state}

  def on_transition(:ready, :publish, _, state),
    do: {:ok, :ready, state}
end

# Infinitomata.start_link Infi
# Infinitomata.start_fsm(Infi, "F_1", SimpleFSM, %{foo: 42})
