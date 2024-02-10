# ![Finitomata](https://raw.githubusercontent.com/am-kantox/finitomata/master/stuff/finitomata-48x48.png) Finitomata    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/finitomata/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/finitomata/workflows/Dialyzer/badge.svg)

**The FSM boilerplate based on callbacks**

---

## Bird View

`Finitomata` provides a boilerplate for [FSM](https://en.wikipedia.org/wiki/Finite-state_machine) implementation, allowing to concentrate on the business logic rather than on the process management and transitions/events consistency tweaking.

It reads a description of the FSM from a string in [PlantUML](https://plantuml.com/en/state-diagram), [Mermaid](https://mermaid.live), or even custom format. 

> ### Syntax Definition {: .tip}
>
> `Mermaid` **state diagram** format is literally the same as `PlantUML`, so if you want to use it, specify `syntax: :state_diagram` and
> if you want to use **mermaid graph**, specify `syntax: :flowchart`. The latter is the default.

Basically, it looks more or less like this

### `PlantUML` / `:state_diagram`

    [*] --> s1 : to_s1
    s1 --> s2 : to_s2
    s1 --> s3 : to_s3
    s2 --> [*] : ok
    s3 --> [*] : ok

### `Mermaid` / `:flowchart`

    s1 --> |to_s2| s2
    s1 --> |to_s3| s3

> ### Using `syntax: :flowchart` {: .tip}
>
> `Mermaid` does not allow to explicitly specify transitions (and hence event names)
> from the starting state and to the end state(s), these states names are implicitly set to `:*`
> and events to `:__start__` and `:__end__` respectively.

`Finitomata` validates the FSM is consistent, namely it has a single initial state, one or more final states, and no orphan states. If everything is OK, it generates a `GenServer` that could be used both alone, and with provided supervision tree. This `GenServer` requires to implement six callbacks

- `on_transition/4` — **mandatory**
- `on_failure/3` — optional
- `on_enter/2` — optional
- `on_exit/2` — optional
- `on_terminate/1` — optional
- `on_timer/2` — optional

All the callbacks do have a default implementation, that would perfectly handle transitions having a single _to_ state and not requiring any additional business logic attached.

Upon start, it moves to the next to initial state and sits there awaiting for the _transition request_. Then it would call an `on_transition/4` callback and move to the next state, or remain in the current one, according to the response.

Upon reaching a final state, it would terminate itself. The process keeps all the history of states it went through, and might have a payload in its state.

## Special Events

If the event name is ended with a bang (e. g. `idle --> |start!| started`) _and_
this event is the only one allowed from this state (there might be several transitions though,)
it’d be considered as _determined_ and FSM will be transitioned into the new state instantly.

If the event name is ended with a question mark (e. g. `idle --> |start?| started`,)
the transition is considered as expected to fail; no `on_failure/2` callback would
be called on failure and no log warning will be printed.

## FSM Tuning and Configuration

### Recurrent Callback

If `timer: non_neg_integer()` option is passed to `use Finitomata`,
then `c:Finitomata.on_timer/2` callback will be executed recurrently.
This might be helpful if _FSM_ needs to update its state from the outside
world on regular basis.

## Automatic FSM Termination

If `auto_terminate: true() | state() | [state()]` option is passed to `use Finitomata`,
the special `__end__` event to transition to the end state will be called automatically
under the hood, if the current state is either listed explicitly, or if the value of
the parameter is `true`.

### Ensuring State Entry

If `ensure_entry: true() | [state()]` option is passed to `use Finitomata`, the transition
attempt will be retried with `{:continue, {:transition, {event(), event_payload()}}}` message
until succeeded. Neither `on_failure/2` callback is called nor warning message is logged.

The payload would be updated to hold `__retries__: pos_integer()` key. If the payload was not a map,
it will be converted to a map `%{payload: payload}`.

## Example

Let’s define the FSM instance

```elixir
defmodule MyFSM do
  @fsm """
  s1 --> |to_s2| s2
  s1 --> |to_s3| s3
  """
  use Finitomata, fsm: @fsm, syntax: :flowchart

  ## or uncomment lines below for `:state_diagram` syntax
  # @fsm """
  # [*] --> s1 : to_s1
  # s1 --> s2 : to_s2
  # s1 --> s3 : to_s3
  # s2 --> [*] : __end__
  # s3 --> [*] : __end__
  # """
  # use Finitomata, fsm: @fsm, syntax: :state_diagram

  @impl Finitomata
  def on_transition(:s1, :to_s2, _event_payload, state_payload),
    do: {:ok, :s2, state_payload}
end
```

Now we can play with it a bit.

```elixir
# or embed into supervision tree using `Finitomata.child_spec()`
{:ok, _pid} = Finitomata.start_link()

Finitomata.start_fsm MyFSM, "My first FSM", %{foo: :bar}
Finitomata.transition "My first FSM", {:to_s2, nil}
Finitomata.state "My first FSM"                    
#⇒ %Finitomata.State{current: :s2, history: [:s1], payload: %{foo: :bar}}

Finitomata.allowed? "My first FSM", :* # state
#⇒ true
Finitomata.responds? "My first FSM", :to_s2 # event
#⇒ false

Finitomata.transition "My first FSM", {:__end__, nil} # to final state
#⇒ [info]  [◉ ⇄] [state: %Finitomata.State{current: :s2, history: [:s1], payload: %{foo: :bar}}]

Finitomata.alive? "My first FSM"
#⇒ false
```

Typically, one would implement all the `on_transition/4` handlers, pattern matching on the state/event.

---

## Installation

```elixir
def deps do
  [
    {:finitomata, "~> 0.1"}
  ]
end
```

## Changelog

- `0.17.0` — [UPD] careful naming and `Finitomata.Throttler`
- `0.16.0` — [UPD] `Infinitomata` as a self-contained distributed implementation leveraging `:pg`
- `0.15.0` — [UPD] support snippet formatting for modern Elixir
- `0.14.6` — [FIX] persistency flaw when loading [credits @peaceful-james]
- `0.14.5` — [FIX] `require Logger` in `Hook`
- `0.14.4` — [FIX] Docs cleanup (credits: @TwistingTwists), `PlantUML` proper entry
- `0.14.3` — [FIX] Draw diagram in docs
- `0.14.2` — [FIX] Stop `Events` process
- `0.14.1` — [FIX] Incorrect detection of superfluous determined transitions
- `0.14.0` — `Finitomata.ExUnit` improvements
- `0.13.0` — compile-time helpers for _FSM_, `Finitomata.ExUnit`
- `0.12.1` — `c:Finitomata.on_start/1` callback
- `0.11.3` — [FIX] better error message for options (credits @ray-sh)
- `0.11.2` — [DEBT] exported `Finitomata.fqn/2`
- `0.11.1` — `Inspect`, `:flowchart`/`:state_diagram` as default parsers, behaviour `Parser`
- `0.11.0` — `{:ok, state_payload}` return from `on_timer/2`, `:persistent_term` to cache state
- `0.10.0` — support for several supervision trees with `id`s, experimental support for persistence scaffold
- `0.9.0` — [FIX] malformed callbacks had the FSM broken
- `0.8.2` — last error is now kept in the state (credits to @egidijusz)
- `0.8.1` — improvements to `:finitomata` compiler
- `0.8.0` — `:finitomata` compiler to warn/hint about not implemented ambiguous transitions
- `0.7.2` — [FIX] `banged!` transitions must not be determined
- `0.6.3` — `soft?` events which do not call `on_failure/2` and do not log errors
- `0.6.2` — `ensure_entry:` option to retry a transition
- `0.6.1` — code cleanup + `auto_terminate:` option to make `:__end__` transition imminent
- `0.6.0` — `on_timer/2` and banged imminent transitions
- `0.5.2` — `state()` type on generated FSMs
- `0.5.1` — fixed specs [credits @egidijusz]
- `0.5.0` — all callbacks but `on_transition/4` are optional, accept `impl_for:` param to `use Finitomata`
- `0.4.0` — allow anonymous FSM instances
- `0.3.0` — `en_entry/2` and `on_exit/2` optional callbacks
- `0.2.0` — [Mermaid](https://mermaid.live) support

[Documentation](https://hexdocs.pm/finitomata).
