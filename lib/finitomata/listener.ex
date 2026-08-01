defmodule Finitomata.Listener do
  @moduledoc """
  The behaviour to be implemented and passed to `use Finitomata` to receive
    all the state transitions notifications.

  ## Modules and processes

  The `listener:` option accepts either an implementation of this behaviour, or anything
    `send/2` accepts (a `t:pid/0`, a `t:port/0`, a registered name, or a
    `{:via, module, term}`/`{name, node}` tuple.) The two are told apart by whether the
    given term is a module exporting `c:after_transition/3`; a process receives
    `{:finitomata, {:transition, state, payload}}` (and
    `{:finitomata, {:fork_error, state, error}}`) messages instead of a callback invocation.

  Because a registered name is an atom too, the distinction is only meaningful for a
    _loaded_ module: `function_exported?/3` answers `false` for a module that has never
    been reached, which is the normal state of affairs in a freshly booted release or at
    the very beginning of a test run. `Finitomata` therefore ensures the module is loaded
    before deciding, so a lazily-loaded listener module is never mistaken for a process
    name (which would raise inside the transition and take the _FSM_ down with it.)

  No explicit `Code.ensure_loaded!/1` call on the listener is needed on the consumer side.
  """

  alias Finitomata.{State, Transition}

  @doc "To be called after a successful transition"
  @callback after_transition(
              id :: Finitomata.fsm_name(),
              state :: Transition.state(),
              payload :: State.payload()
            ) :: :ok

  @doc """
  To be called when a `c:Finitomata.on_fork/2` resolution fails.

  Optional callback; implement it to be notified when the FSM reaches a fork state but the
    fork cannot be resolved (an unknown/ambiguous/missing fork target, a bad return, or a
    raise). `state` is the fork state and `error` is the resolution failure reason.
  """
  @doc since: "0.41.0"
  @callback after_fork_failure(
              id :: Finitomata.fsm_name(),
              state :: Transition.state(),
              error :: any()
            ) :: :ok

  @optional_callbacks after_fork_failure: 3
end
