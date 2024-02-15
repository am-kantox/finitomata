defmodule Finitomata.Pool.Test do
  use ExUnit.Case, async: true

  doctest Finitomata.Pool

  alias Finitomata.Pool.Actor

  @behaviour Actor

  @impl Actor
  def actor(arg, _state) when is_atom(arg) do
    {:ok, arg}
  end

  def actor(_arg, _state) do
    {:error, "Atom required"}
  end

  @impl Actor
  def on_result(atom, id), do: atom |> Atom.to_string() |> tap(&Actor.result_logger(&1, id))

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
