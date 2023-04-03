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

  setup_schema = [
    fsm: [
      required: true,
      type: :non_empty_keyword_list,
      doc: "The _FSM_ declaration to be used in tests.",
      keys: [
        id: [
          required: false,
          type: :any,
          default: nil,
          doc: "The ID of the `Finitomata` tree."
        ],
        implementation: [
          required: true,
          type: {:custom, Finitomata, :behaviour, [Finitomata]},
          doc: "The implementatoin of `Finitomata` (the module with `use Finitomata`.)"
        ],
        name: [
          required: false,
          type: :string,
          doc: "The name of the `Finitomata` instance."
        ],
        payload: [
          required: true,
          type: :any,
          doc: "The initial payload for the _FSM_ to start with."
        ],
        options: [
          required: false,
          type: :keyword_list,
          default: [],
          doc: "Additional options to use in _FSM_ initialization.",
          keys: [
            transition_count: [
              required: false,
              type: :non_neg_integer,
              doc: "The expected by `Mox` number of transitions to handle."
            ]
          ]
        ]
      ]
    ],
    context: [
      required: false,
      type: :keyword_list,
      doc: "The additional context to be passed to actual `ExUnit.Callbacks.setup/2` call."
    ]
  ]

  @setup_schema NimbleOptions.new!(setup_schema)
  defmacro setup_finitomata(do: block) do
    quote generated: true, location: :keep do
      fsm_setup = NimbleOptions.validate!(unquote(block), unquote(Macro.escape(@setup_schema)))

      fsm = Keyword.get(fsm_setup, :fsm)
      @fini_id fsm[:id]
      @fini_impl fsm[:implementation]
      @fini_name fsm[:name]
      @fini_payload fsm[:payload]
      @fini_options fsm[:options]

      @fini_context Keyword.get(fsm_setup, :context)

      setup ctx do
        init_finitomata(
          @fini_id,
          @fini_impl,
          @fini_name || ctx.test,
          @fini_payload,
          @fini_options
        )

        Keyword.put(@fini_context, :__pid__, self())
      end
    end
  end

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
      assert_payload do
        user_data.counter ~> 2
        internals.pid ~> ^parent
      end
      # or: assert_payload %{user_data: %{counter: 2}, internals: %{pid: ^parent}}
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

            {:assert_payload, _meta, [[do: matches]]} ->
              do_handle_matches(matches)

            {:assert_payload, _meta, [assertion]} ->
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
            bind_quoted: [impl: impl, event_name: event_name(event_payload), states: states] do
        [state | continuation] = states

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
            missing_states: expected_continuation -- continuation,
            unknown_states: continuation -- expected_continuation
        end
      end

    init_ast =
      quote generated: true, location: :keep do
        fsm_name =
          {:via, Registry, {Finitomata.Supervisor.registry_name(unquote(id)), unquote(name)}}
      end

    assertion_ast =
      states_with_assertions
      |> Enum.with_index()
      |> Enum.map(fn {{to_state, ast}, idx} ->
        transition_ast =
          if idx == 0 do
            quote do: Finitomata.transition(unquote(id), unquote(name), unquote(event_payload))
          end

        action_ast =
          quote generated: true, location: :keep do
            to_state = unquote(to_state)
            assert_receive {:on_transition, ^fsm_name, ^to_state, payload}, 1_000
            unquote(ast)
          end

        quote generated: true, location: :keep do
          unquote(transition_ast)
          unquote(action_ast)
        end
      end)

    quote generated: true, location: :keep do
      unquote(init_ast)
      unquote(guard_ast)
      unquote(assertion_ast)
    end
  end

  defmacro test_path(test_name, id \\ nil, impl, name, initial_payload, context \\ [], do: block),
    do: do_test_path(test_name, id, impl, name, initial_payload, context, do: unblock(block))

  defp do_test_path(test_name, id, impl, name, initial_payload, context, do: block) do
    # IO.inspect({test_name, id, impl, name, initial_payload, context, block}, label: "test_path")

    expanded_context = [
      quote do
        init_finitomata(
          unquote(id),
          unquote(impl),
          unquote(name),
          unquote(initial_payload)
        )
      end
      | Enum.map(context, fn {var, val} ->
          {:=, [], [Macro.var(var, nil), val]}
        end)
    ]

    transitions =
      block
      |> unblock()
      |> Enum.map(fn {:->, _meta, [[event_payload], state_assertions]} ->
        state_assertions_ast =
          state_assertions
          |> unblock()
          |> Enum.map(fn {:assert_state, meta, [state, [do: block]]} ->
            {:->, meta, [[state], {:__block__, meta, unblock(block)}]}
          end)

        do_assert_transition(id, impl, name, event_payload, do: state_assertions_ast)
      end)

    quote generated: true, location: :keep do
      test unquote(test_name), _fix_me do
        unquote(expanded_context)
        unquote(transitions)
      end
    end
  end

  # defp escape(contents) do
  #   Macro.escape(contents, unquote: true)
  # end

  defp event_name({event, _payload}) when is_atom(event), do: event
  defp event_name(event) when is_atom(event), do: event

  defp unblock({:__block__, _, block}), do: unblock(block)
  defp unblock(block), do: List.wrap(block)

  defp do_handle_matches([]), do: []

  defp do_handle_matches([{:->, meta, [[{_, _, _} = var], match_ast]} | more]),
    do: do_handle_matches([{:~>, meta, [var, match_ast]} | more])

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
