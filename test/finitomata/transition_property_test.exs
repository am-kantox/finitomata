defmodule Finitomata.TransitionPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Finitomata.Transition

  # Builds a valid linear-chain Mermaid FSM over the given intermediate states, e.g.
  #   "s1 --> |to_s2| s2\ns2 --> |to_s3| s3". Such an FSM is valid by construction:
  #   a single initial state (implicit `:*` before `s1`), one final transition, no orphans.
  defp chain_fsm(states) do
    states
    |> Enum.zip(tl(states))
    |> Enum.map_join("\n", fn {from, to} -> "#{from} --> |to_#{to}| #{to}" end)
  end

  # Reference reachability: plain BFS from the entry state over the parsed transitions.
  defp reachable_states(transitions) do
    edges = Enum.group_by(transitions, & &1.from, & &1.to)

    transitions
    |> Transition.entry()
    |> then(&bfs([&1], edges, MapSet.new([&1])))
    |> Enum.reject(&(&1 == :*))
  end

  defp bfs([], _edges, seen), do: MapSet.to_list(seen)

  defp bfs([state | rest], edges, seen) do
    nexts = edges |> Map.get(state, []) |> Enum.reject(&MapSet.member?(seen, &1))
    seen = Enum.reduce(nexts, seen, &MapSet.put(&2, &1))
    bfs(rest ++ nexts, edges, seen)
  end

  property "a linear chain FSM validates, exposes its states, and keeps every state reachable" do
    check all n <- integer(2..8) do
      states = for i <- 1..n, do: :"s#{i}"

      assert {:ok, transitions} = states |> chain_fsm() |> Finitomata.Mermaid.parse()

      # every declared (non-`:*`) state is present
      assert Enum.sort(Transition.states(transitions, true)) == Enum.sort(states)

      # the library's reachability agrees with a reference BFS, and covers all states
      assert Enum.sort(reachable_states(transitions)) == Enum.sort(states)

      # a chain has exactly one start-to-end path, and it visits every state in order
      assert [%Transition.Path{from: :*, to: :*} = path] = Transition.shortest_paths(transitions)
      visited = path.path |> Enum.map(&elem(&1, 1)) |> Enum.reject(&(&1 == :*))
      assert visited == states
    end
  end

  property "branching to several final states yields one straight path per branch" do
    check all branches <- integer(2..5) do
      # entry --> |b_i| leaf_i  (each leaf is a distinct final state)
      fsm =
        Enum.map_join(1..branches, "\n", fn i -> "entry --> |b#{i}| leaf#{i}" end)

      assert {:ok, transitions} = Finitomata.Mermaid.parse(fsm)

      paths = Transition.straight_paths(transitions)
      assert Enum.all?(paths, &match?(%Transition.Path{from: :*, to: :*}, &1))
      assert Enum.count(paths) == branches
    end
  end
end
