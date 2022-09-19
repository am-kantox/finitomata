# ![Finitomata](https://raw.githubusercontent.com/am-kantox/finitomata/master/stuff/finitomata-48x48.png) Finitomata    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/finitomata/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/finitomata/workflows/Dialyzer/badge.svg)

**The FSM boilerplate based on callbacks**

---

## Bird View

`Finitomata` provides a boilerplate for [FSM](https://en.wikipedia.org/wiki/Finite-state_machine) implementation, allowing to concentrate on the business logic rather than on the process management and transitions/events consistency tweaking.

It reads a description of the FSM from a string in [PlantUML](https://plantuml.com/en/state-diagram), [Mermaid](https://mermaid.live), or even custom format. Basically, it looks more or less like this

### `PlantUML`

    [*] --> s1 : to_s1
    s1 --> s2 : to_s2
    s1 --> s3 : to_s3
    s2 --> [*] : ok
    s3 --> [*] : ok

### `Mermaid`

    s1 --> |to_s2| s2
    s1 --> |to_s3| s3

> ### Note {: .tip}
>
> `mermaid` does not allow to explicitly specify transitions (and hence event names)
> from the starting state and to the end state(s), these states names are implicitly set to `:*`
> and events to `:__start__` and `:__end__` respectively.

`Finitomata` validates the FSM is consistent, namely it has a single initial state, one or more final states, and no orphan states. If everything is OK, it generates a `GenServer` that could be used both alone, and with provided supervision tree. This `GenServer` requires to implement three callbacks

- `on_transition/4` — mandatory
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
this transition is the only one allowed from this state, it’d be considered as
_determined_ and FSM will be transitioned into the new state instantly.

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
  @plantuml """
  [*] --> s1 : to_s1
  s1 --> s2 : to_s2
  s1 --> s3 : to_s3
  s2 --> [*] : ok
  s3 --> [*] : ok
  """

  use Finitomata, fsm: @plantuml, syntax: Finitomata.PlantUML
  ## or uncomment lines below for Mermaid syntax
  # @mermaid """
  # s1 --> |to_s2| s2
  # s1 --> |to_s3| s3
  # """
  # use Finitomata, fsm: @mermaid, syntax: Finitomata.Mermaid

  @impl Finitomata
  def on_transition(:s1, :to_s2, event_payload, state_payload),
    do: {:ok, :s2, state_payload}
end
```

Now we can play with it a bit.

```elixir
children = [Finitomata.child_spec()]
Supervisor.start_link(children, strategy: :one_for_one)

Finitomata.start_fsm MyFSM, "My first FSM", %{foo: :bar}
Finitomata.transition "My first FSM", {:to_s2, nil}
Finitomata.state "My first FSM"                    
#⇒ %Finitomata.State{current: :s2, history: [:s1], payload: %{foo: :bar}}

Finitomata.allowed? "My first FSM", :* # state
#⇒ true
Finitomata.responds? "My first FSM", :to_s2 # event
#⇒ false

Finitomata.transition "My first FSM", {:ok, nil} # to final state
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
