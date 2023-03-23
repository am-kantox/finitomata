defmodule Finitomata.Transition.Test do
  use ExUnit.Case

  doctest Finitomata.Transition

  alias Finitomata.Test.Transition

  test "loops" do
    assert [
             %Finitomata.Transition.Path{
               from: :started,
               to: :started,
               path: [accept: :accepted, accept: :accepted, reject: :rejected, restart: :started]
             },
             %Finitomata.Transition.Path{
               from: :started,
               to: :started,
               path: [accept: :accepted, reject: :rejected, restart: :started]
             },
             %Finitomata.Transition.Path{
               from: :started,
               to: :started,
               path: [reject: :rejected, restart: :started]
             },
             %Finitomata.Transition.Path{
               from: :accepted,
               to: :accepted,
               path: [accept: :accepted]
             },
             %Finitomata.Transition.Path{
               from: :accepted,
               to: :accepted,
               path: [reject: :rejected, restart: :started, accept: :accepted]
             },
             %Finitomata.Transition.Path{
               from: :rejected,
               to: :rejected,
               path: [restart: :started, accept: :accepted, accept: :accepted, reject: :rejected]
             },
             %Finitomata.Transition.Path{
               from: :rejected,
               to: :rejected,
               path: [restart: :started, accept: :accepted, reject: :rejected]
             },
             %Finitomata.Transition.Path{
               from: :rejected,
               to: :rejected,
               path: [restart: :started, reject: :rejected]
             }
           ] = Finitomata.Transition.loops(Transition.fsm())
  end
end
