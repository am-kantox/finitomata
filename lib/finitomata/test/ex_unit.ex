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

  @doc """
  Setups `Finitomata` for testing in the case and/or in `ExUnit.Case.describe/2` block.

  It would effectively init the _FSM_ with an underlying call to `init_finitomata/5`,
    and put `finitomata` key into `context`, assigning `:test_pid` subkey to the `pid`
    of the running test process, and mixing `:context` content into test context.

  Although one might pass the name, it’s more convenient to avoid doing it, in this case
    the name would be assigned from the test name, which guarantees uniqueness of
    _FSM_s running in concurrent environment.

  It should return the keyword which would be validated with `NimbleOptions` schema

  #{NimbleOptions.docs(@setup_schema)}

  _Example:_

  ```elixir
  describe "MyFSM tests" do
    setup_finitomata do
      parent = self()

      [
        fsm: [implementation: MyFSM, payload: %{}],
        context: [parent: parent]
      ]
    end

    …
  ```
  """
  defmacro setup_finitomata(do: block) do
    quote generated: true, location: :keep do
      fsm_setup = NimbleOptions.validate!(unquote(block), unquote(Macro.escape(@setup_schema)))

      @fini Keyword.fetch!(fsm_setup, :fsm)
      @fini_context Keyword.get(fsm_setup, :context, [])
      @fini_implementation @fini[:implementation]

      setup ctx do
        fini =
          @fini
          |> update_in([:name], fn
            nil -> ctx.test
            other -> other
          end)
          |> Map.new()

        init_finitomata(fini.id, @fini_implementation, fini.name, fini.payload, fini.options)
        Keyword.put(@fini_context, :finitomata, %{test_pid: self(), fsm: Map.new(fini)})
      end
    end
  end

  @doc """
  This macro initiates the _FSM_ implementation specified by arguments passed.

  **NB** it’s not recommended to use low-level helpers, normally one should
    define an _FSM_ in `setup_finitomata/1` block, which would initiate
    the _FSM_ amongs other things.

  _Arguments:_

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
  Convenience macro to assert a transition initiated by `event_payload`
    argument on the _FSM_ defined by the test context previously setup
    with a call to `setup_finitomata/1`.

  Last regular argument in a call to `assert_transition/3` would be an
    `event_payload` in a form of `{event, payload}`, or just `event`
    for no payload.

  `to_state` argument would be matched to the resulting state of the transition,
    and `block` accepts validation of the `payload` after transition in a form of

  ```elixir
  test "some", ctx do
    assert_transition ctx, {:increase, 1} do
      :counted ->
        assert_payload do
          user_data.counter ~> 2
          internals.pid ~> ^parent
        end
        # or: assert_payload %{user_data: %{counter: 2}, internals: %{pid: ^parent}}

        assert_receive {:increased, 2}
    end
  end
  ```
  """
  defmacro assert_transition(ctx, event_payload, do: block) do
    quote do
      fsm =
        case unquote(ctx) do
          %{finitomata: %{fsm: fsm}} ->
            fsm

          other ->
            raise TestTransitionError,
              message:
                "in order to use `assert_transition/3` one should declare _FSM_ in `setup_finitomata/1` callback"
        end

      assert_transition(fsm.id, fsm.implementation, fsm.name, unquote(event_payload),
        do: unquote(block)
      )
    end
  end

  @doc """
  Convenience macro to assert a transition initiated by `event_payload`
    argument on the _FSM_ defined by first three arguments.

  **NB** it’s not recommended to use low-level helpers, normally one should
    define an _FSM_ in `setup_finitomata/1` block and use `assert_transition/3`
    or even better `test_path/3`.

  Last regular argument in a call to `assert_transition/3` would be an
    `event_payload` in a form of `{event, payload}`, or just `event`
    for no payload.

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
        file = Keyword.get(meta, :file, "‹unknown›")

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

            {:refute_receive, _, _} = ast ->
              [ast]

            {:assert_receive, _, _} = ast ->
              [ast]

            other ->
              content = other |> Macro.to_string() |> String.split("\n") |> hd() |> String.trim()

              raise TestTransitionError,
                message:
                  :elixir_errors.format_snippet(
                    {line, 0},
                    file,
                    "clauses in a call to `assert_transition/5` must be either `:ok`, or `payload.inner.struct ~> match`, given:\n",
                    content <> " …",
                    :error,
                    [],
                    nil
                  )
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

  @doc """
  Convenience macro to test the whole _Finitomata_ path,
    from starting to ending state.

  Must be used with a `setup_finitomata/1` callback.

  _Example:_

  ```elixir
    test_path "The only path", %{finitomata: %{test_pid: parent}} do
      {:start, self()} ->
        assert_state :started do
          assert_payload do
            internals.counter ~> 1
            pid ~> ^parent
          end

          assert_receive {:on_start, ^parent}
        end

      :do ->
        assert_state :done do
          assert_receive :on_do
        end

        assert_state :* do
          assert_receive :on_end
        end
    end
  ```
  """
  defmacro test_path(test_name, ctx \\ quote(do: _), do: block) do
    quote generated: true, location: :keep do
      test unquote(test_name), unquote(ctx) = ctx do
        fsm =
          case ctx do
            %{finitomata: %{fsm: fsm}} ->
              fsm

            other ->
              raise TestTransitionError,
                message:
                  "in order to use `test_path/3` one should declare _FSM_ in `setup_finitomata/1` callback"
          end

        test_path_transitions(
          fsm.id,
          fsm.implementation,
          fsm.name,
          do: unquote(block)
        )
      end
    end
  end

  @doc false
  defmacro test_path(test_name, id \\ nil, impl, name, initial_payload, context \\ [], do: block),
    do: do_test_path(test_name, id, impl, name, initial_payload, context, do: unblock(block))

  defp do_test_path(test_name, id, impl, name, initial_payload, context, do: block) do
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

    quote generated: true, location: :keep do
      test unquote(test_name), ctx do
        unquote(expanded_context)
        test_path_transitions(unquote(id), unquote(impl), unquote(name), do: unquote(block))
      end
    end
  end

  @doc false
  defmacro test_path_transitions(id, impl, name, do: block) do
    block
    |> unblock()
    |> Enum.map(fn {:->, _meta, [[event_payload], state_assertions]} ->
      state_assertions_ast =
        state_assertions
        |> unblock()
        |> Enum.map(fn {:assert_state, meta, [state, [do: block]]} ->
          {:->, meta, [[state], {:__block__, meta, unblock(block)}]}
        end)

      {event_payload,
       do_assert_transition(id, impl, name, event_payload, do: state_assertions_ast)}
    end)
  end

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
