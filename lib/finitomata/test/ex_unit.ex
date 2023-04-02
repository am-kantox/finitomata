defmodule Finitomata.ExUnit do
  @moduledoc """
  Helpers and assertions to make `Finitomata` implementation easily testable.
  """
  alias Finitomata.TestTransitionError

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
        fsm_name = {:via, Registry, {Finitomata.Supervisor.registry_name(id), name}}
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

  assert_transition id, impl, name, {:increase, 1} do
    :counted ->
      assert_state do
        user_data.counter ~> 2
        internals.pid ~> ^parent
      end
      # or: assert_state %{user_data: %{counter: 2}, internals: %{pid: ^parent}}
      assert_receive {:increased, 2}
  end
  ```
  """
  defmacro assert_transition(id \\ nil, impl, name, event_payload, do: block),
    do: do_assert_transition(id, impl, name, event_payload, do: block)

  defp do_assert_transition(id, impl, name, event_payload, do: block) do
    states_with_assertions =
      block
      |> unblock()
      |> Enum.map(fn {:->, meta, [[state], conditions]} ->
        line = Keyword.get(meta, :line, 1)

        assertions =
          conditions
          |> unblock()
          |> Enum.flat_map(fn
            :ok ->
              []

            {:assert_state, _meta, [[do: matches]]} ->
              do_handle_matches(matches)

            {:assert_state, _meta, [assertion]} ->
              [quote(do: assert(unquote(assertion) = payload))]

            {:assert_receive, _, _} = ast ->
              [ast]

            other ->
              content = other |> Macro.to_string() |> String.split("\n") |> hd() |> String.trim()

              raise TestTransitionError,
                message:
                  "clauses in a call to `assert_transition/5` must be either `:ok`, or `payload.inner.struct ~> match`, given:\n" <>
                    Exception.format_snippet(%{content: content <> " …", offset: 0}, line)
          end)

        {state, assertions}
      end)

    if Enum.empty?(states_with_assertions) do
      raise TestTransitionError,
        message:
          "handler in `assert_transition/5` for event #{inspect(event_payload)} must have at least one clause"
    end

    states = Keyword.keys(states_with_assertions)

    guard_ast =
      quote generated: true,
            location: :keep,
            bind_quoted: [impl: impl, event: event_payload, states: states] do
        [state | continuation] = states

        event_name =
          case event do
            {event_name, _} -> event_name
            event_name -> event_name
          end

        transitions =
          :fsm
          |> impl.__config__()
          |> Enum.filter(&match?(%Finitomata.Transition{to: ^state, event: ^event_name}, &1))

        case states -- impl.__config__(:states) do
          [] -> :ok
          some -> raise TestTransitionError, transition: transitions, unknown_states: some
        end

        expected_continuation =
          :transitions
          |> Finitomata.Transition.continuation(
            state,
            Keyword.values(impl.__config__(:hard))
          )
          |> Enum.map(& &1.to)

        [continuation, expected_continuation]
        |> Enum.map(&MapSet.new/1)
        |> Enum.reduce(&MapSet.equal?/2)
        |> unless do
          raise TestTransitionError,
            transition: transitions,
            missing_states: expected_continuation -- continuation
        end
      end

    assertion_ast =
      states_with_assertions
      |> Enum.with_index()
      |> Enum.map(fn {{to_state, ast}, idx} ->
        quote generated: true, location: :keep do
          fsm_name =
            {:via, Registry, {Finitomata.Supervisor.registry_name(unquote(id)), unquote(name)}}

          if unquote(idx) == 0,
            do: Finitomata.transition(unquote(id), unquote(name), unquote(event_payload))

          to_state = unquote(to_state)

          assert_receive {:on_transition, ^fsm_name, ^to_state, payload}, 1_000

          unquote(ast)
        end
      end)

    [guard_ast | assertion_ast]
  end

  defmacro test_path(id \\ nil, impl, name, do: block),
    do: do_test_path(id, impl, name, do: unblock(block))

  defp do_test_path(id, impl, name, do: block) do
    IO.inspect({id, impl, name, block}, label: "test_path")

    [
      {:->, [line: 262],
       [
         [start: 42],
         {:started, [line: 263],
          [
            {:~>, [line: 263],
             [
               {{:., [line: 263], [{:internals, [line: 263], nil}, :pid]},
                [no_parens: true, line: 263], []},
               {:^, [line: 263], [{:parent, [line: 263], nil}]}
             ]}
          ]}
       ]},
      {:->, [line: 265],
       [
         [:do],
         {:done, [line: 266],
          [
            [
              do:
                {:~>, [line: 266],
                 [
                   {:pid, [line: 266], nil},
                   {:^, [line: 266], [{:parent, [line: 266], nil}]}
                 ]}
            ]
          ]}
       ]}
    ]

    # block =
    #   block
    #   |> Enum.map(fn {:->, _meta, [[{_, _, _} = var], match_ast]} ->
    #     path = var |> estructura_path() |> Enum.reverse()

    #     quote do
    #       assert unquote(match_ast) = get_in(to_state.payload, unquote(path))
    #     end
    #   end)
    #   |> IO.inspect(label: "block")

    quote generated: true, location: :keep do
    end
  end

  defp unblock({:__block__, _, block}), do: unblock(block)
  defp unblock(block), do: List.wrap(block)

  defp do_handle_matches([]), do: []

  defp do_handle_matches([{:~>, _meta, [{_, _, _} = var, match_ast]} | more]) do
    path = var |> estructura_path() |> Enum.reverse()

    match =
      quote do
        assert unquote(match_ast) = get_in(payload, unquote(path))
      end

    [match | do_handle_matches(more)]
  end

  defp do_handle_matches(any), do: any |> unblock() |> do_handle_matches()
end
