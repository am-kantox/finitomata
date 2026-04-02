# Finitomata Cheatsheet

## Quick Start

### 1. Add the dependency

```elixir
def deps do
  [{:finitomata, "~> 0.30"}]
end
```

### 2. Add the compiler (optional, recommended)

```elixir
def project do
  [
    compilers: [:finitomata | Mix.compilers()],
    ...
  ]
end
```

The `:finitomata` compiler validates FSM definitions at compile time and warns about unimplemented ambiguous transitions.

### 3. Define the FSM

```elixir
defmodule MyFSM do
  @fsm """
  idle --> |wake!| ready
  ready --> |process| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  @impl Finitomata
  def on_transition(:ready, :process, _event_payload, state_payload) do
    {:ok, :done, state_payload}
  end
end
```

### 4. Start and use

```elixir
# Start the supervision tree (or embed Finitomata.child_spec() into yours)
{:ok, _pid} = Finitomata.start_link()

# Start an FSM instance
Finitomata.start_fsm(MyFSM, "my_fsm_1", %{foo: :bar})

# Trigger a transition
Finitomata.transition("my_fsm_1", {:process, %{some: :data}})

# Query the state
Finitomata.state("my_fsm_1")
```

---

## FSM Syntax

Two syntaxes are supported. The default is `:flowchart` (Mermaid).

### Mermaid / `:flowchart` (default)

```
idle --> |wake| ready
ready --> |process| done
ready --> |fail| broken
```

With `:flowchart`, the starting (`[*] --> first_state`) and ending (`last_state --> [*]`) transitions are **implicit**. The entry event is `:__start__` and the exit event is `:__end__`.

### PlantUML / `:state_diagram`

```
[*] --> idle : wake
idle --> ready : start
ready --> done : process
done --> [*] : finish
```

With `:state_diagram`, you **must** explicitly declare transitions from `[*]` (start) and to `[*]` (end).

Set the syntax via:

```elixir
use Finitomata, fsm: @fsm, syntax: :state_diagram
```

---

## Event Types

Events drive the FSM from state to state. Finitomata recognizes three _kinds_ of events based on the event name suffix.

### Normal events

Events without any special suffix. The transition must be triggered explicitly by calling `Finitomata.transition/3`.

```
ready --> |process| done
```

If the transition fails (callback returns `{:error, _}` or raises), `on_failure/3` is called and a warning is logged.

### Hard (determined) events -- `:foo!`

Events whose name ends with `!`. When the FSM enters a state from which a hard event is the **only** outgoing event, that event fires **automatically** (via `{:continue, ...}`).

```
idle --> |init!| ready
ready --> |do!| done
done --> |finish!| ended
```

Hard events must be _determined_ -- the event must be the sole event from a given state (though it may lead to multiple target states if `on_transition/4` resolves the ambiguity).

Common use: chaining states that need no external trigger, initialization sequences, guaranteed progression.

```elixir
# The FSM will automatically move idle -> ready -> done -> ended
# without any manual transition call, as long as on_transition/4
# resolves each step.
```

### Soft events -- `:foo?`

Events whose name ends with `?`. When the transition fails, **no** `on_failure/3` callback is invoked and **no** warning is logged. The failure is silently swallowed (debug-level log only).

```
ready --> |try_call?| done
```

Common use: optimistic transitions that may legitimately fail (e.g., checking an external service, polling for readiness).

### Summary table

```
Suffix  Kind    Auto-fire?  on_failure/3 called?  Warning logged?
------  ------  ----------  ---------------------  ---------------
(none)  normal  no          yes                    yes
  !     hard    yes *       yes                    yes
  ?     soft    no          no                     no
```

\* Only when the event is the sole outgoing event from the state.

### Combining hard + soft

An event **cannot** have both `!` and `?` in its name. Choose one.

---

## Payloads

Finitomata carries two distinct kinds of payload.

### State payload (the FSM's persistent data)

This is the data that lives for the entire lifetime of the FSM instance. It is passed as the initial payload when starting the FSM, and it is threaded through every `on_transition/4` call.

```elixir
# Pass it at startup
Finitomata.start_fsm(MyFSM, "my_fsm", %{counter: 0, items: []})

# It arrives as the 4th argument in on_transition/4
def on_transition(:ready, :process, _event_payload, state_payload) do
  new_payload = %{state_payload | counter: state_payload.counter + 1}
  {:ok, :done, new_payload}
end
```

The state payload can be any term -- a map, a struct, a keyword list, or even a plain value. Maps are the most common choice.

### Event payload (per-transition data)

This is the data attached to a single transition call. It is passed as the 3rd argument to `on_transition/4`.

```elixir
# Attach event payload to a transition
Finitomata.transition("my_fsm", {:process, %{user_id: 42, action: :approve}})

# Receive it in the callback
def on_transition(:ready, :process, event_payload, state_payload) do
  # event_payload is %{user_id: 42, action: :approve, __retries__: 1}
  {:ok, :done, Map.put(state_payload, :last_user, event_payload.user_id)}
end
```

Internally, Finitomata wraps event payloads:
- If the event payload is a map, `__retries__` key is injected/incremented.
- If the event payload is not a map, it is wrapped as `%{payload: original_value, __retries__: 1}`.
- If `nil`, it becomes `%{__retries__: 1}`.

When calling `transition/3` with just an event atom (no payload):

```elixir
Finitomata.transition("my_fsm", :process)
# equivalent to
Finitomata.transition("my_fsm", {:process, nil})
```

### Delayed transitions

Transitions can be delayed:

```elixir
# Fire :process after 5 seconds
Finitomata.transition("my_fsm", {:process, %{data: 42}}, 5_000)
```

---

## Initial State and Startup

### How the FSM starts

1. `Finitomata.start_fsm/4` is called with a module, a name, and a payload.
2. The `GenServer` is started; `init/1` is called.
3. The `on_start/1` callback (if implemented) is invoked with the initial payload.
4. The FSM transitions from `*` (the internal starting pseudo-state) to the entry state via the entry event (`:__start__` for flowchart, or whatever the `[*] --> state : event` defines for state_diagram).

### `on_start/1` callback

The `on_start/1` callback is optional. It allows you to modify the initial payload or control the startup behavior.

```elixir
@impl Finitomata
def on_start(payload) do
  # Fetch some data, validate, enrich the payload, etc.
  {:continue, Map.put(payload, :started_at, DateTime.utc_now())}
end
```

Return values:

```
Return value              Effect
------------------------  ------------------------------------------------
:ok                       Proceed normally, payload unchanged
:ignore                   Proceed normally, payload unchanged
{:continue, new_payload}  Proceed with modified payload (auto-enter start)
{:ok, new_payload}        Set new payload but do NOT auto-transition
                          to the entry state; you must trigger it manually
```

When `{:ok, new_payload}` is returned, the FSM stays in the `*` state and the entry transition must be triggered explicitly. This is useful when you need to wait for an external signal before the FSM begins its lifecycle.

If `on_start/1` raises, the FSM process will stop.

### Passing the parent PID

By default, `self()` (the calling process) is stored as the parent. You can override it:

```elixir
Finitomata.start_fsm(MyFSM, "my_fsm", %{parent: some_pid, foo: :bar})
```

The `:parent` key is extracted from the payload and stored in `State.parent`; it does not appear in the actual state payload.

---

## Callbacks Reference

### `on_transition/4` -- mandatory

The core callback. Called on every transition attempt.

```elixir
@impl Finitomata
def on_transition(current_state, event, event_payload, state_payload) do
  {:ok, next_state, new_state_payload}
  # or
  {:error, reason}
end
```

For ambiguous transitions (same event can lead to different states), you **must** return the correct target state. For determined transitions (only one possible target), the default implementation handles it automatically.

### `on_start/1` -- optional

Called once during initialization. See the "Initial State and Startup" section above.

### `on_enter/2` -- optional, pure

Called after entering a new state.

```elixir
@impl Finitomata
def on_enter(:ready, state) do
  Logger.info("Entered ready state")
  :ok
end
```

### `on_exit/2` -- optional, pure

Called before leaving a state.

```elixir
@impl Finitomata
def on_exit(:ready, state) do
  Logger.info("Leaving ready state")
  :ok
end
```

### `on_failure/3` -- optional, pure

Called when a transition fails (not called for soft `?` events).

```elixir
@impl Finitomata
def on_failure(event, event_payload, state) do
  Logger.warning("Transition #{event} failed: #{inspect(state.last_error)}")
  :ok
end
```

### `on_terminate/1` -- optional, pure

Called when the FSM reaches the final state and is about to terminate.

```elixir
@impl Finitomata
def on_terminate(state) do
  Logger.info("FSM terminated: #{inspect(state.payload)}")
  :ok
end
```

### `on_timer/2` -- optional, mutating

Called recurrently when `timer: milliseconds` is set.

```elixir
use Finitomata, fsm: @fsm, timer: 5_000

@impl Finitomata
def on_timer(:ready, state) do
  :ok                                         # do nothing
  # or
  {:ok, new_payload}                          # update payload
  # or
  {:transition, :some_event, new_payload}     # trigger a transition
  # or
  {:transition, {:event, ev_payload}, new_payload} # with event payload
  # or
  {:reschedule, 10_000}                       # change the timer interval
end
```

---

## `use Finitomata` Options

```elixir
use Finitomata,
  fsm: @fsm,                    # required -- the FSM definition string
  syntax: :flowchart,           # :flowchart (default) | :state_diagram
  impl_for: :all,               # :all | :none | list of callback names
  auto_terminate: false,         # true | state_atom | [state_atoms]
  timer: false,                  # false | pos_integer (ms)
  ensure_entry: [],              # true | [state_atoms]
  hibernate: false,              # true | false | [state_atoms]
  cache_state: true,             # cache payload in :persistent_term
  persistency: nil,              # module implementing Finitomata.Persistency
  listener: nil,                 # module | :mox | {:mox, FallbackModule}
  forks: [],                     # [{state, {event, fork_module}}, ...]
  shutdown: 5_000                # GenServer shutdown timeout
```

### `auto_terminate`

When the FSM reaches a state from which the **only** event is `:__end__` (the implicit termination event), `auto_terminate` will fire that event automatically.

- `true` -- auto-terminate from any such state
- `:some_state` -- auto-terminate only from that state
- `[:s1, :s2]` -- auto-terminate from these states

### `ensure_entry`

When a transition to certain states fails, it will be retried indefinitely via `{:continue, ...}`. The event payload will contain `__retries__: count`.

### `hibernate`

Hibernate the GenServer process between transitions to save memory.

- `true` -- hibernate after every transition
- `[:idle, :waiting]` -- hibernate only in these states

### `impl_for`

Controls which optional callbacks get a default (no-op) implementation injected.

- `:all` -- all optional callbacks get defaults
- `:none` -- you must implement everything yourself
- `[:on_enter, :on_exit]` -- only these get defaults

---

## Structured State with `defstate`

Use the `defstate/1` macro to define a typed, validated payload structure (backed by `Estructura.Nested`):

```elixir
defmodule MyFSM do
  use Finitomata, fsm: @fsm

  defstate %{
    counter: :integer,
    retries: %{attempts: :integer, errors: [:string]}
  }
end
```

This gives you coercion, validation, and generation for the payload shape.

---

## Querying the FSM

```elixir
# Full state (includes current state, history, payload, etc.)
Finitomata.state("my_fsm")

# Just the payload (cached if cache_state: true)
Finitomata.state("my_fsm", :payload)

# Just the current state atom
Finitomata.state("my_fsm", :state)

# Cached payload (fast, from :persistent_term)
Finitomata.state("my_fsm", :cached)

# Custom projection
Finitomata.state("my_fsm", fn state -> state.payload.counter end)

# Can we transition to state :done?
Finitomata.allowed?("my_fsm", :done)

# Can we handle event :process right now?
Finitomata.responds?("my_fsm", :process)

# Is this FSM alive?
Finitomata.alive?("my_fsm")
```

---

## Distributed FSM with `Infinitomata`

For cluster-wide FSMs, use `Infinitomata` -- a drop-in replacement that distributes FSMs across nodes using `:pg` process groups.

```elixir
# In your supervision tree
{Infinitomata, nil}

# Start, transition, query -- same API
Infinitomata.start_fsm(MyFSM, "my_fsm", %{foo: :bar})
Infinitomata.transition("my_fsm", {:process, nil})
Infinitomata.state("my_fsm")
```

Implement `Finitomata.ClusterInfo` for custom node discovery (e.g., with `libring`).

---

## Supervision Tree

### Embedding into your application

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      Finitomata.child_spec()
      # or with a custom id:
      # Finitomata.child_spec(:my_fini_id)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Using a custom id

When you need multiple independent Finitomata supervision trees:

```elixir
Finitomata.child_spec(:tree_a)
Finitomata.child_spec(:tree_b)

# Pass the id to all calls
Finitomata.start_fsm(:tree_a, MyFSM, "fsm_1", %{})
Finitomata.transition(:tree_a, "fsm_1", :process)
```

---

## Typical Patterns

### Initialization chain

```
idle --> |init!| configuring
configuring --> |configure!| ready
ready --> |process| done
```

The FSM auto-transitions through `idle -> configuring -> ready` without external triggers, then waits for `:process`.

### Retry loop with soft events

```
ready --> |try_call?| done
ready --> |fallback| failed
```

Attempt `:try_call?` -- if it fails silently, the FSM stays in `:ready` for another attempt (e.g., triggered by `on_timer/2`).

### Polling with timer

```elixir
use Finitomata, fsm: @fsm, timer: 5_000

def on_timer(:waiting, state) do
  case check_external_service() do
    {:ok, result} ->
      {:transition, :proceed, Map.put(state.payload, :result, result)}
    :not_ready ->
      :ok  # stay in :waiting, timer will fire again
  end
end
```

### Ambiguous transitions

```
ready --> |process| success
ready --> |process| failure
```

The same event leads to different states -- `on_transition/4` **must** resolve which:

```elixir
def on_transition(:ready, :process, event_payload, state_payload) do
  case do_work(event_payload) do
    :ok -> {:ok, :success, state_payload}
    :error -> {:ok, :failure, state_payload}
  end
end
```
