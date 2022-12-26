defmodule EctoIntegration.Data.Post.FSM do
  @fsm """
    empty --> |edit| draft
    draft --> |edit| draft
    draft --> |publish| published
    draft --> |delete| deleted
    published --> |edit| draft
    published --> |delete| deleted
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, persistency: Finitomata.Persistency.Protocol
end
