defmodule Finitomata.Pool.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Pool

  def actor(arg) when is_atom(arg) do
    {:ok, arg}
  end

  def actor(_arg) do
    {:error, "Atom required"}
  end

  def on_result(atom), do: Atom.to_string(atom)

  setup do
    pool =
      start_supervised!(
        Finitomata.Pool,
        Finitomata.Pool.pool_spec(id: Pool, actor: &actor/1, on_result: &on_result/1)
      )

    Finitomata.Pool.initialize(Pool, nil)

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

    assert count_of_processes == 8
  end
end
