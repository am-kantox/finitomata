defmodule Finitomata.ExUnit do
  @moduledoc """
  Helpers and assertions to make `Finitomata` implementation easily testable.
  """

  @doc false
  def estructura_path({{:., _, [{hd, _, _}, tl]}, _, []}) do
    [tl | estructura_path(hd)]
  end

  def estructura_path({leaf, _, args}) when args in [nil, []], do: estructura_path(leaf)
  def estructura_path(leaf), do: [leaf]

  @doc """
  This macro initiates the _FSM_ implementation specified by arguments passed
   
  - `id` — a `Finitomata` instance, carrying multiple _FSM_s
  - `impl` — the module implementing _FSM_ (having `use Finitomata` clause)
  - `name` — the name of the _FSM_
  - `payload` — the initial payload for this _FSM_
  - `options` — the options to control the test, such as
    - `transition_count` — the number of expectations to declare (defaults to number of states)

  Once called, this macro will start `Finitomata.Suprevisor` with the `id` given,
    define a mox for `impl` unless already efined,
    `Mox.allow/3` the _FSM_ to call testing process,
    and expectations as a listener to `after_transition/3` callback,
    sending a message of a shape `{:on_transition, id, state, payload}` to test process.

  Then it’ll start _FSM_ and ensure it has entered `Finitomata.Transition.entry/2` state.
  """
  defmacro init_finitomata(id \\ nil, impl, name, payload, options \\ []) do
    require_ast = quote generated: true, location: :keep, do: require(unquote(impl))

    init_ast =
      quote generated: true,
            location: :keep,
            bind_quoted: [id: id, impl: impl, name: name, payload: payload, options: options] do
        mock = Module.concat(impl, "Mox")
        fsm_name = {:via, Registry, {Finitomata.Supervisor.fq_module(id, Registry, true), name}}
        transition_count = Keyword.get(options, :transition_count, Enum.count(impl.states()))

        parent = self()

        unless Code.ensure_loaded?(mock),
          do: Mox.defmock(mock, for: Finitomata.Listener)

        start_supervised({Finitomata.Supervisor, id: id})

        mock
        |> allow(parent, fn -> GenServer.whereis(fsm_name) end)
        |> expect(:after_transition, transition_count, fn id, state, payload ->
          parent |> send({:on_transition, id, state, payload}) |> then(fn _ -> :ok end)
        end)

        Finitomata.start_fsm(id, impl, name, payload)

        entry_state = impl.entry()
        assert_receive {:on_transition, ^fsm_name, ^entry_state, ^payload}, 1_000
      end

    [require_ast, init_ast]
  end

  @doc """
  Convenience macro as assert a transition initiated by `event_payload`
    argument on the _FSM_ defined by first three arguments.

  `to_state` argument would be matched to the resulting state of the transition,
    and `block` accepts validation of the `payload` after transition in a form of

  ```elixir
  parent = self()

  assert_transition id, impl, name, {:increase, 1}, :counted do
    user_data.counter -> 2
    internals.pid -> ^parent
  end
  ```
  """
  defmacro assert_transition(id \\ nil, impl, name, event_payload, to_state, do: block) do
    block =
      block
      |> Enum.map(fn {:->, _meta, [[{_, _, _} = var], match_ast]} ->
        path = var |> estructura_path() |> Enum.reverse()

        quote do
          assert unquote(match_ast) = get_in(to_state.payload, unquote(path))
        end
      end)

    quote generated: true, location: :keep do
      Finitomata.transition(unquote(id), unquote(name), unquote(event_payload))

      to_state = Finitomata.state(unquote(id), unquote(name), :full)

      case unquote(to_state) do
        nil ->
          assert is_nil(to_state)

        state when state in unquote(impl).config(:states) ->
          fsm_name =
            {:via, Registry,
             {Finitomata.Supervisor.fq_module(unquote(id), Registry, true), unquote(name)}}

          entry_state = unquote(to_state)
          assert_receive {:on_transition, ^fsm_name, ^entry_state, payload}, 1_000

          assert %Finitomata.State{current: unquote(to_state)} = to_state

          unquote(block)
      end
    end
  end
end
