defmodule Finitomata.Pool.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Pool

  @behaviour Finitomata.Pool.Actor

  @impl Finitomata.Pool.Actor
  def actor(arg, _state) when is_atom(arg) do
    {:ok, arg}
  end

  def actor(_arg, _state) do
    {:error, "Atom required"}
  end

  @impl Finitomata.Pool.Actor
  def on_result(atom), do: Atom.to_string(atom)

  setup do
    pool =
      start_supervised!(
        Finitomata.Pool,
        Finitomata.Pool.pool_spec(id: Pool, implementation: __MODULE__)
      )

    Finitomata.Pool.initialize(Pool, %{foo: 42})

    %{pool: pool}
  end

  test "Pooling" do
    count_of_processes =
      1..50
      |> Enum.flat_map(fn _i ->
        Finitomata.Pool.run(Pool, :atom)
        assert_receive {:transition, :success, pid_ok, {:atom, :atom, "atom"}}

        Finitomata.Pool.run(Pool, "string")
        assert_receive {:transition, :failure, pid_ko, {"string", "Atom required", nil}}

        [pid_ok, pid_ko]
      end)
      |> Enum.uniq()
      |> Enum.count()

    assert count_of_processes == System.schedulers_online()
  end
end
