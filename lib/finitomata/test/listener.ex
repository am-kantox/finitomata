defmodule Finitomata.ExUnit.Listener do
  @moduledoc """
  A dependency-free `Finitomata.Listener` implementation for tests.

  Declaring `listener: Finitomata.ExUnit.Listener` on an _FSM_ lets `Finitomata.ExUnit`
    drive and assert transitions **without `Mox`**. On every successful transition it
    forwards a `{:on_transition, fsm_name, state, payload}` message — the exact shape the
    `Finitomata.ExUnit` assertions expect — to the test process that registered itself for
    that _FSM_. A failed `c:Finitomata.on_fork/2` resolution is forwarded the same way as
    `{:on_fork_failure, fsm_name, fork_state, error}`.

  The test process is looked up through the per-id `Finitomata` `Registry` that
    `setup_finitomata/1` (via `init_finitomata/6`) already starts, so no extra process or
    global state is involved, and the registration is dropped automatically when the test
    process exits.

  ## Usage

  ```elixir
  defmodule MyFSM do
    use Finitomata, fsm: @fsm, listener: Finitomata.ExUnit.Listener
  end
  ```

  In `:test`/`:dev` only, pick the listener conditionally to keep production lean:

  ```elixir
  @listener if Mix.env() == :test, do: Finitomata.ExUnit.Listener
  use Finitomata, fsm: @fsm, listener: @listener
  ```

  Then write the test exactly as with the `:mox` listener, but without `import Mox`:

  ```elixir
  import Finitomata.ExUnit

  describe "MyFSM" do
    setup_finitomata do
      [fsm: [implementation: MyFSM, payload: %{}]]
    end

    test_path "happy path", _ctx do
      :go -> assert_state :done
    end
  end
  ```
  """

  @behaviour Finitomata.Listener

  @key :__finitomata_exunit_listener__

  @doc """
  Registers the calling (test) process to receive `{:on_transition, fsm_name, state, payload}`
    notifications for the _FSM_ identified by `fsm_name` (its fully-qualified `:via` tuple).
  """
  @spec register(Finitomata.fsm_name()) :: :ok
  def register({:via, Registry, {registry, name}}) do
    case Registry.register(registry, {@key, name}, nil) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, _owner}} -> :ok
    end
  end

  def register(_other), do: :ok

  @impl Finitomata.Listener
  def after_transition(id, state, payload) do
    with {:via, Registry, {registry, name}} <- id,
         [{pid, _value} | _] <- safe_lookup(registry, {@key, name}) do
      send(pid, {:on_transition, id, state, payload})
    end

    :ok
  end

  @impl Finitomata.Listener
  def after_fork_failure(id, state, error) do
    with {:via, Registry, {registry, name}} <- id,
         [{pid, _value} | _] <- safe_lookup(registry, {@key, name}) do
      send(pid, {:on_fork_failure, id, state, error})
    end

    :ok
  end

  @spec safe_lookup(atom(), term()) :: [tuple()]
  defp safe_lookup(registry, key) do
    Registry.lookup(registry, key)
  rescue
    ArgumentError -> []
  end
end
