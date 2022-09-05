# ![Finitomata](https://raw.githubusercontent.com/am-kantox/finitomata/master/stuff/finitomata-48x48.png) Finitomata    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/finitomata/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/finitomata/workflows/Dialyzer/badge.svg)

**The FSM boilerplate based on callbacks**

## Introduction

---

### Bird View

`Finitomata` provides a boilerplate for [FSM](https://en.wikipedia.org/wiki/Finite-state_machine) implementation, allowing to concentrate on the business logic rather than on the process management and transitions/events consistency tweaking.

It reads a description of the FSM from a string in [PlantUML](https://plantuml.com/en/state-diagram), [Mermaid](https://mermaid.live), or even custom format. Basically, it looks more or less like this

#### `PlantUML`

    [*] --> s1 : to_s1
    s1 --> s2 : to_s2
    s1 --> s3 : to_s3
    s2 --> [*] : ok
    s3 --> [*] : ok

#### `Mermaid`

    s1 --> |to_s2| s2
    s1 --> |to_s3| s3

> #### Note {: .tip}
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

All the callbacks do have a default implementation, that would perfectly handle transitions having a single _to_ state and not requiring any additional business logic attached.

Upon start, it moves to the next to initial state and sits there awaiting for the _transition request_. Then it would call an `on_transition/4` callback and move to the next state, or remain in the current one, according to the response.

Upon reachiung a final state, it would terminate itself. The process keeps all the history of states it went through, and might have a payload in its state.

### Example

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

- `0.5.2` — `state()` type on generated FSMs
- `0.5.1` — fixed specs [credits @egidijusz]
- `0.5.0` — all callbacks but `on_transition/4` are optional, accept `impl_for:` param to `use Finitomata`
- `0.4.0` — allow anonymous FSM instances
- `0.3.0` — `en_entry/2` and `on_exit/2` optional callbacks
- `0.2.0` — [Mermaid](https://mermaid.live) support

[Documentation](https://hexdocs.pm/finitomata).
