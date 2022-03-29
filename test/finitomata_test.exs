defmodule FinitomataTest do
  use ExUnit.Case
  doctest Finitomata
  doctest Finitomata.PlantUML

  test "greets the world" do
    assert Finitomata.hello() == :world
  end
end
