defmodule Finitomata.ExUnit do
  @moduledoc ~S"""
  Helpers and assertions to make `Finitomata` implementation easily testable.

  ## Testing with `Finitomata.ExUnit`

  There are several steps needed to enable extended testing with `Finitomata.ExUnit`.

  In the first place, `mox` dependency should be included in your `mix.exs` project file

  ```elixir
  {:mox, "~> 1.0", only: [:test]}
  ```

  Then, the `Finitomata` declaration should include a listener. If you already have the
    listener, it should be changed to `Mox` in `:test` environment, and the respecive `Mox`
    should be defined somewhere in `test/support` or like

  ```elixir
  @listener (if Mix.env() == :test, do: MyFSM.Mox, else: MyFSM.Listener)
  use Finitomata, fsm: @fsm, listener: @listener
  # or
  # use Finitomata, fsm: @fsm, listener: {:mox, MyFSM.Listener}
  ```

  If you don’t have an actual listener, the special `:mox` value for `listener` would do
    everything, including an actual `Mox` declaration in `test` environment.

  ```elixir
  use Finitomata, fsm: @fsm, listener: :mox
  ```

  The last thing you need, `import Mox` into your test file which also does
    `import Finitomata.ExUnit`. That’s it, now your code is ready to use `Finitomata.ExUnit`
    fancy testing.

  ## Example

  Consider the following simple FSM

  ```elixir
  defmodule Turnstile do
    @fsm ~S[
      ready --> |on!| closed
      opened --> |walk_in| closed
      closed --> |coin_in| opened
      closed --> |switch_off| switched_off
    ]
    use Finitomata, fsm: @fsm, auto_terminate: true

    @impl Finitomata
    def on_transition(:opened, :walk_in, _payload, state) do
      {:ok, :closed, update_in(state, [:data, :passengers], & &1 + 1)}
    end
    def on_transition(:closed, :coin_in, _payload, state) do
      {:ok, :opened, state}
    end
    def on_transition(:closed, :switch_off, _payload, state) do
      {:ok, :switched_off, state}
    end
  end
  ```

  Of course, in the real life, one would not only collect the total number of passengers passed
    in the state, but also validate the coin value to let in or fail a transition, but
    for the demonstration purposes this one is already good enough.

  We now want to test it works as expected. Without `Finitomata.ExUnit`, one would
    write the test like below

  ```elixir
  # somewhere else → Mox.defmock(Turnstile.Mox, for: Finitomata.Listener)
  test "standard approach" do
    start_supervised(Finitomata.Supervisor)

    fini_name = "Turnstile_1"
    fsm_name = {:via, Registry, {Finitomata.Registry, fini_name}}

    Finitomata.start_fsm(Turnstile, fini_name, %{data: %{passengers: 0}})

    Finitomata.transition(fini_name, :coin_in)
    assert %{data: %{passengers: 0}} = Finitomata.state(Turnstile, "Turnstile_1", :payload)

    Finitomata.transition(fini_name, :walk_in)
    assert %{data: %{passengers: 1}} = Finitomata.state(Turnstile, "Turnstile_1", :payload)

    Finitomata.transition(fini_name, :switch_off)

    Process.sleep(200)
    refute Finitomata.alive?(Turnstile, "Turnstile_1")
  end
  ```

  At the first glance, there is nothing wrong with this approach, but it requires
    an enormous boilerplate, it cannot check it’s gone without using `Process.sleep/1`,
    but most importantly, it does not allow testing intermediate states.

  If the FSM has instant transitions (named with a trailing bang, like `foo!`) which
    are invoked automatically by `Finitomata` itself, there is no way to test intermediate
    states with the approach above.

  OK, let’s use `Mox` then (assuming `Turnstile.Mox` has been declared and added
    as a listener in test environment to `use Finitomata`)

  ```elixir
  # somewhere else → Mox.defmock(Turnstile.Mox, for: Finitomata.Listener)
  test "standard approach" do
    start_supervised(Finitomata.Supervisor)

    fini_name = "Turnstile_1"
    fsm_name = {:via, Registry, {Finitomata.Registry, fini_name}}
    parent = self()

    Turnstile.Mox
    |> allow(parent, fn -> GenServer.whereis(fsm_name) end)
    |> expect(:after_transition, 4, fn id, state, payload ->
      parent |> send({:on_transition, id, state, payload}) |> then(fn _ -> :ok end)
    end)

    Finitomata.start_fsm(Turnstile, fini_name, %{data: %{passengers: 0}})

    Finitomata.transition(fini_name, :coin_in)
    assert_receive {:on_transition, ^fsm_name, :opened, %{data: %{passengers: 0}}}
    # assert %{data: %{passengers: 0}} = Finitomata.state(Turnstile, "Turnstile_1", :payload)

    Finitomata.transition(fini_name, :walk_in)
    assert_receive {:on_transition, ^fsm_name, :closed, %{data: %{passengers: 1}}}
    # assert %{data: %{passengers: 1}} = Finitomata.state(Turnstile, "Turnstile_1", :payload)

    Finitomata.transition(fini_name, :switch_off)
    assert_receive {:on_transition, ^fsm_name, :switched_off, %{data: %{passengers: 1}}}

    Process.sleep(200)
    refute Finitomata.alive?(Turnstile, "Turnstile_1")
  end
  ```

  That looks better, but there is still too much of boilerplate. Let’s see how it’d look like
    with `Finitomata.ExUnit`.

  ```elixir
  describe "Turnstile" do
    setup_finitomata do
      parent = self()
      initial_passengers = 42

      [
        fsm: [implementation: Turnstile, payload: %{data: %{passengers: initial_passengers}}],
        context: [passengers: initial_passengers]
      ]
    end

    test_path "respectful passenger", %{passengers: initial_passengers} do
      :coin_in ->
        assert_state :opened do
          assert_payload do
            data.passengers ~> ^initial_passengers
          end
        end

      :walk_in ->
        assert_state :closed do
          assert_payload do
            data.passengers ~> one_more when one_more == 1 + initial_passengers
          end
        end

      :switch_off ->
        assert_state :switched_off
        assert_state :*
    end
  ```

  With this approach, one could test the payload in the intermediate states, and validate
    messages received from the FSM with `assert_receive/3`.

  No other code besides `assert_state/2`, `assert_payload/1`, and `ExUnit.Assertions.assert_receive/3` is
    permitted to fully isolate the FSM execution from side effects.

  ## Custom environments

  In the bigger application, it might be not convenient to declare mocks for
    each and every case when `Finitomata`/`Infinitomata` might have been called under the hood.

  For such cases, one might pass `mox_envs: :finitomata` to an FSM declaration,
    or set such a config options as `config :finitomata, :mox_envs, :finitomata`. That would result
    in mocks implemented for `listener: :mox` in this environment(s) _only_.

  Then the tests should have been split into two groups assuming the finitomata tests
    were generated with the mix task (see below)

  ```
  mix test --exclude finitomata
  MIX_ENV=finitomata mix test --exclude test --include finitomata
  ```

  Don’t forget to add `:finitomata` env to the list of envs where `mox` is installed

  ## Test Scaffold Generation

  > ### `mix` tasks to simplify testing {: .info}
  >
  > One might generate the tests scaffold for all possible paths in the FSM with a `mix` task
  >
  >  ```bash
  >  mix finitomata.generate.test --module MyApp.FSM
  >  ```
  >
  > besides the mandatory `--module ModuleWithUseFinitomata` argument, it also accepts
  > `--dir` and `--file` arguments (defaulted to `test/finitomata` and
  > `Macro.underscore(module) <> "_test.exs`) respectively.)

  ## Testing without `Mox`

  If you’d rather not depend on `Mox`, declare the _FSM_ with the built-in
    `Finitomata.ExUnit.Listener` instead of `:mox`:

  ```elixir
  use Finitomata, fsm: @fsm, listener: Finitomata.ExUnit.Listener
  # or, test-only:
  # @listener if Mix.env() == :test, do: Finitomata.ExUnit.Listener
  # use Finitomata, fsm: @fsm, listener: @listener
  ```

  Everything else (`setup_finitomata/1`, `test_path/3`, `assert_transition/3`,
    `assert_state/2`, `assert_payload/1`) works exactly the same — just drop `import Mox`.
    See `Finitomata.ExUnit.Listener` for details.

  ## Matching the payload

  `assert_payload/1` matches the carried payload with the `~>` operator, whose left-hand
    side is a (possibly nested) path resolved with `get_in/2`. The payload therefore has to
    implement the `Access` behaviour — the easiest way is to declare it with `defstate/1`
    (which builds an `Estructura.Nested`), or to use a struct that derives `Access`. A plain
    map works out of the box.

  ## Asserting failures

  A failed transition (a soft `event?`, an `{:error, _}` from `on_transition/4`, or a raise)
    does not notify the listener, so there is nothing to `assert_receive`. Use
    `assert_no_transition/3` to assert that the _FSM_ stayed put and to inspect the error:

  ```elixir
  assert_no_transition ctx, :reject? do
    assert %Finitomata.Error{reason: :rejected} = last_error
    assert :started = state.current
  end
  ```

  Inside the block, `state` (the whole `t:Finitomata.State.t/0`), `payload`, and `last_error`
    are bound for plain assertions.

  ## Timer transitions

  In `test_path/3`, the `:_` clause stands for a timer tick (`Finitomata.timer_tick/2`); the
    payload is read straight from the running _FSM_, so timer-driven `on_timer/2` callbacks
    can be asserted just like regular transitions:

  ```elixir
  test_path "ticking", _ctx do
    :_ ->
      assert_state :processing do
        assert_payload do: processing ~> true
      end
  end
  ```

  ## Configurable timeouts

  The `assert_receive` timeout used while awaiting transition notifications (default `1_000`
    ms), the `refute_receive` timeout used by `assert_no_transition/3` (default `100` ms),
    and the message-flush timeout (default `100` ms) are all configurable:

  ```elixir
  config :finitomata,
    ex_unit_assert_receive_timeout: 5_000,
    ex_unit_refute_receive_timeout: 200,
    ex_unit_flush_timeout: 200
  ```

  ## Property-based testing

  `event_generator/1` returns a `StreamData` generator over the _FSM_’s events, which can be
    combined with `ExUnitProperties` to fuzz event sequences and assert global invariants
    (for instance, that the _FSM_ never crashes and always rests in a valid state).
  """

  require Logger
  alias Finitomata.ExUnit.Listener
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
          type: {:or, [:atom, {:custom, Finitomata, :behaviour, [Finitomata]}]},
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
              doc:
                "When given, the exact `Mox.expect/4` count of transitions to handle; " <>
                  "by default a `Mox.stub/3` is installed and the count is not asserted."
            ]
          ]
        ]
      ]
    ],
    mocks: [
      required: false,
      type: {:list, :atom},
      default: [],
      doc: "Additional mocks to be passed to the test."
    ],
    context: [
      required: false,
      type: :keyword_list,
      default: [],
      doc: "The additional context to be passed to actual `ExUnit.Callbacks.setup/2` call."
    ]
  ]

  @setup_schema NimbleOptions.new!(setup_schema)

  @doc """
  Asserts the state within `test_path/3` context.

  Typically, one would assert the state and the payload within it as shown below
  ```elixir
  assert_state :idle do
    assert_payload do
      data.counter ~> value when is_integer(value)
      data.listener ~> ^pid # assuming `pid` variable is in context
    end
  end
  ```
  """
  @dialyzer {:no_return, {:assert_state, 1}}
  @dialyzer {:no_return, {:assert_state, 2}}
  def assert_state(state, do_block \\ []) do
    _ = state
    _ = do_block

    raise "`assert_state/2` may only be used inside a `test_path/3` or `assert_transition/3` block"
  end

  @doc """
  Asserts the payload within `test_path/3` and `assert_transition/3`.

  ```elixir
  assert_payload do
    counter ~> 42
    user.id ~> ^user_id # assuming `user_id` variable is in context
  end
  ```
  """
  @dialyzer {:no_return, {:assert_payload, 1}}
  def assert_payload(do_block) do
    _ = do_block

    raise "`assert_payload/1` may only be used inside a `test_path/3` or `assert_transition/3` block"
  end

  @doc false
  @spec do_flush(keyword()) :: keyword()
  def do_flush(messages \\ []) do
    receive do
      msg -> do_flush([msg | messages])
    after
      flush_timeout() ->
        messages
        |> Enum.map(fn {:on_transition, _fsm, state, payload} -> {state, payload} end)
        |> Enum.reverse()
    end
  end

  @doc false
  @spec assert_receive_timeout() :: timeout()
  def assert_receive_timeout,
    do: Application.get_env(:finitomata, :ex_unit_assert_receive_timeout, 1_000)

  @doc false
  @spec refute_receive_timeout() :: timeout()
  def refute_receive_timeout,
    do: Application.get_env(:finitomata, :ex_unit_refute_receive_timeout, 100)

  @doc false
  @spec flush_timeout() :: timeout()
  def flush_timeout,
    do: Application.get_env(:finitomata, :ex_unit_flush_timeout, 100)

  @doc """
  Returns a `StreamData` generator yielding the externally-triggerable events of the _FSM_
    implemented by `impl`, for property-based fuzzing of event sequences.

  The internal `:__start__`/`:__end__` events are excluded.

  ```elixir
  property "never crashes" do
    check all events <- list_of(Finitomata.ExUnit.event_generator(MyFSM), min_length: 1) do
      # drive `events` against a running FSM and assert your invariants
    end
  end
  ```
  """
  @spec event_generator(Finitomata.implementation()) ::
          StreamData.t(Finitomata.Transition.event())
  def event_generator(impl) do
    impl.__config__(:events)
    |> Kernel.--([:__start__, :__end__])
    |> StreamData.member_of()
  end

  @doc false
  def assertions_to_states({:__block__, _, states}) do
    Enum.flat_map(states, fn
      {:assert_state, _, [state | _]} -> [state]
      _ -> []
    end)
  end

  def assertions_to_states(_), do: []

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

        init_finitomata(
          fini.id,
          @fini_implementation,
          fini.name,
          fini.payload,
          fini.options,
          Keyword.get(unquote(block), :mocks, [])
        )

        @fini_context
        |> Keyword.put(:finitomata, %{
          test_pid: self(),
          auto_init_msgs: Finitomata.ExUnit.do_flush(),
          fsm: Map.new(fini)
        })
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
    - `transition_count` — when given, the exact `Mox.expect/4` count for the listener;
      by default a `Mox.stub/3` is installed instead, so the number of transitions is not
      asserted (only ignored when the _FSM_ uses `Finitomata.ExUnit.Listener`)

  Once called, this macro will start `Finitomata.Suprevisor` with the `id` given and start
    the _FSM_, ensuring it has entered `Finitomata.Transition.entry/2` state.

  When the _FSM_ uses `listener: Finitomata.ExUnit.Listener` the test process is registered
    to receive transition notifications directly (no `Mox` involved). Otherwise a mox for
    `impl` is defined (unless already defined), `Mox.allow/3`-ed to be called from the _FSM_,
    and stubbed/expected on `after_transition/3` to send `{:on_transition, id, state, payload}`
    to the test process.
  """
  @doc deprecated: "Use `setup_finitomata/1` instead"

  defmacro init_finitomata(id \\ nil, impl, name, payload, options \\ [], mocks \\ []) do
    require_ast = quote generated: true, location: :keep, do: require(unquote(impl))

    # Resolve the listener at compile time so that a Mox-free _FSM_ never has `Mox` calls
    #   generated into its test (and therefore does not require `Mox` to be available).
    listener =
      case Macro.expand(impl, __CALLER__) do
        module when is_atom(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :__config__, 1),
            do: module.__config__(:listener),
            else: nil

        _other ->
          nil
      end

    init_ast =
      if listener == Listener do
        quote generated: true,
              location: :keep,
              bind_quoted: [id: id, impl: impl, name: name, payload: payload] do
          fsm_name = {:via, Registry, {Finitomata.Supervisor.registry_name(id), name}}

          start_supervised({Finitomata.Supervisor, id: id})
          Listener.register(fsm_name)

          {:ok, _fsm_pid} = Finitomata.start_fsm(id, impl, name, payload)

          entry_state = impl.entry()

          assert_receive {:on_transition, ^fsm_name, ^entry_state, ^payload},
                         Finitomata.ExUnit.assert_receive_timeout()
        end
      else
        quote generated: true,
              location: :keep,
              bind_quoted: [
                id: id,
                impl: impl,
                name: name,
                payload: payload,
                options: options,
                mocks: mocks
              ] do
          mocker = &Module.concat(&1, "Mox")

          mock =
            if is_map(payload),
              do: Map.get_lazy(payload, :mock, fn -> mocker.(impl) end),
              else: mocker.(impl)

          fsm_name = {:via, Registry, {Finitomata.Supervisor.registry_name(id), name}}
          parent = self()

          unless Code.ensure_loaded?(mock),
            do:
              raise("Listener mock must be defined for `Finitomata` to use `ex_unit` extensions")

          start_supervised({Finitomata.Supervisor, id: id})

          Enum.each(mocks, &allow(&1, parent, fn -> GenServer.whereis(fsm_name) end))

          listener_fun = fn id, state, payload ->
            parent |> send({:on_transition, id, state, payload}) |> then(fn _ -> :ok end)
          end

          mock = allow(mock, parent, fn -> GenServer.whereis(fsm_name) end)

          case Keyword.fetch(options, :transition_count) do
            {:ok, transition_count} ->
              expect(mock, :after_transition, transition_count, listener_fun)

            :error ->
              stub(mock, :after_transition, listener_fun)
          end

          {:ok, _fsm_pid} = Finitomata.start_fsm(id, impl, name, payload)

          entry_state = impl.entry()

          assert_receive {:on_transition, ^fsm_name, ^entry_state, ^payload},
                         Finitomata.ExUnit.assert_receive_timeout()
        end
      end

    [require_ast, init_ast]
  end

  @doc false
  # Resolves the `%{fsm: …}` map from the test context. Kept as a function (rather than an
  #   inline `case` in the macros) so the match is analysed here, with an untyped argument,
  #   instead of at the call site — where the context type is narrowed and would make the
  #   fallback clause look unreachable to the compiler.
  @spec fetch_fsm!(term(), String.t()) :: term()
  def fetch_fsm!(%{finitomata: %{fsm: fsm}}, _macro), do: fsm

  def fetch_fsm!(_ctx, macro) do
    raise Finitomata.TestTransitionError,
      message:
        "in order to use `#{macro}` one should declare the _FSM_ in a `setup_finitomata/1` callback"
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

  Any matchers should be available on the right side of `~>` operator in the same way as the first
    argument of [`match?/2`](https://hexdocs.pm/elixir/Kernel.html#match?/2).

  Each argument might be matched several times.

  ```elixir
    ...
    assert_payload do
      user_data.counter ~> {:foo, _}
      internals.pid ~> pid when is_pid(pid)
    end
  ```
  """
  defmacro assert_transition(ctx, event_payload, do: block) do
    quote do
      fsm = Finitomata.ExUnit.fetch_fsm!(unquote(ctx), "assert_transition/3")

      assert_transition(fsm.id, fsm.implementation, fsm.name, unquote(event_payload),
        do: unquote(block)
      )
    end
  end

  @doc """
  Asserts that `event_payload` does **not** transition the _FSM_ defined by the test context
    (set up with `setup_finitomata/1`), and exposes the resulting error for inspection.

  A failed transition (a soft `event?`, an `{:error, _}` returned from `on_transition/4`, or
    a raise) does not notify the listener, so it cannot be awaited with `assert_receive/3`.
    This macro drives the event, asserts that no transition notification arrives (within
    `Finitomata.ExUnit.refute_receive_timeout/0`), and binds `state` (the whole
    `t:Finitomata.State.t/0`), `payload`, and `last_error` for plain assertions in the block:

  ```elixir
  test "rejects", ctx do
    assert_no_transition ctx, :reject? do
      assert %Finitomata.Error{reason: :rejected} = last_error
      assert :started = state.current
    end
  end
  ```
  """
  defmacro assert_no_transition(ctx, event_payload, do: block) do
    quote generated: true, location: :keep do
      fsm = Finitomata.ExUnit.fetch_fsm!(unquote(ctx), "assert_no_transition/3")

      fsm_name = {:via, Registry, {Finitomata.Supervisor.registry_name(fsm.id), fsm.name}}

      Finitomata.transition(fsm.id, fsm.name, unquote(event_payload))

      refute_receive {:on_transition, ^fsm_name, _state, _payload},
                     Finitomata.ExUnit.refute_receive_timeout()

      var!(state) = :sys.get_state(fsm_name)
      var!(payload) = var!(state).payload
      var!(last_error) = var!(state).last_error

      unquote(block)
    end
  end

  @doc """
  Convenience macro to assert a transition initiated by `event_payload`
    argument on the _FSM_ defined by first three arguments.

  **NB** it’s not recommended to use low-level helpers, normally one should
    define an _FSM_ in `setup_finitomata/1` block and use `assert_transition/3`
    or even better `test_path/3`.

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

  _See:_ `assert_transition/3` for examples of matches and arguments
  """
  @doc deprecated: "Use `assert_transition/3` instead"

  defmacro assert_transition(id \\ nil, impl, name, event_payload, do: block),
    do: do_assert_transition(id, impl, name, event_payload, __CALLER__, nil, do: block)

  defp do_assert_transition(id, impl, name, event_payload, caller, matches, do: block) do
    states_with_assertions =
      block
      |> unblock()
      |> Enum.map(fn {:->, meta, [[state], conditions]} ->
        line = Keyword.get(meta, :line, caller.line)
        file = Keyword.get(meta, :file, caller.file)
        {state, clause_assertions(conditions, line, file)}
      end)

    if Enum.empty?(states_with_assertions) do
      raise TestTransitionError,
        message:
          "handler in `assert_transition/5` for event #{inspect(event_payload)} must have at least one clause"
    end

    states = Keyword.keys(states_with_assertions)

    init_ast =
      quote generated: true, location: :keep do
        fsm_name =
          {:via, Registry, {Finitomata.Supervisor.registry_name(unquote(id)), unquote(name)}}
      end

    assertion_ast =
      states_with_assertions
      |> Enum.with_index()
      |> Enum.map(fn {{to_state, ast}, idx} ->
        transition_assertion_ast(to_state, ast, idx, id, name, event_payload, matches)
      end)

    quote generated: true, location: :keep do
      unquote(init_ast)
      unquote(coverage_guard_ast(impl, event_payload, states))
      unquote(assertion_ast)
    end
  end

  # Parses the right-hand side of an `assert_transition` clause into the list of inner
  #   assertion ASTs (`assert_payload`, `assert_receive`, `refute_receive`, or `:ok`).
  defp clause_assertions(conditions, line, file) do
    conditions
    |> unblock()
    |> Enum.flat_map(fn
      :ok ->
        []

      {:assert_payload, _meta, [[do: matches]]} ->
        do_handle_matches(matches)

      {:assert_payload, _meta, [assertion]} ->
        [do_handle_matches_with_guards(assertion)]

      {:refute_receive, _, _} = ast ->
        [ast]

      {:assert_receive, _, _} = ast ->
        [ast]

      other ->
        content = other |> Macro.to_string() |> String.split("\n")
        raise TestTransitionError, message: format_assertion(line, file, content)
    end)
  end

  # Builds the compile-time path-coverage check that warns (via `IO.warn/1`) when the
  #   asserted continuation diverges from the states reachable for the transition.
  defp coverage_guard_ast(impl, event_payload, states) do
    quote generated: true,
          location: :keep,
          bind_quoted: [impl: impl, event_name: event_name(event_payload), states: states] do
      [state | continuation] = states

      transitions =
        :fsm
        |> impl.__config__()
        |> Enum.filter(&match?(%Finitomata.Transition{to: ^state, event: ^event_name}, &1))

      case states -- impl.__config__(:states) do
        [] ->
          :ok

        some ->
          IO.warn(
            TestTransitionError.message(%TestTransitionError{
              message: nil,
              transition: transitions,
              unknown_states: some
            })
          )
      end

      expected_continuation =
        impl.__config__(:hard)
        |> Keyword.values()
        |> Enum.flat_map(&Finitomata.Transition.flatten/1)

      expected_continuations =
        :transitions
        |> Finitomata.Transition.continuation(state, expected_continuation)
        |> Enum.map(&Enum.map(&1, fn %Finitomata.Transition{to: to} -> to end))

      shortened_expected_continuations =
        expected_continuations
        |> Enum.map(fn expected_continuation ->
          case Enum.chunk_by(expected_continuation, &(&1 == state)) do
            [] -> []
            [_] -> []
            [_before | _rest] = chunks -> List.last(chunks)
          end
        end)
        |> Enum.reject(&(&1 == []))

      expected = Enum.uniq([[] | expected_continuations ++ shortened_expected_continuations])

      if continuation not in expected do
        IO.warn(
          TestTransitionError.message(%TestTransitionError{
            message: nil,
            transition: transitions,
            missing_states: expected -- continuation,
            unknown_states: continuation -- expected
          })
        )
      end
    end
  end

  # Builds the drive-the-transition plus assert-the-result AST for a single clause.
  defp transition_assertion_ast(to_state, ast, idx, id, name, event_payload, matches) do
    transition_ast =
      cond do
        idx == 0 and is_nil(matches) ->
          quote do: Finitomata.transition(unquote(id), unquote(name), unquote(event_payload))

        matches == :__timer_event__ ->
          quote do: Finitomata.timer_tick(unquote(id), unquote(name))

        true ->
          []
      end

    action_ast =
      case matches do
        nil ->
          quote generated: true, location: :keep do
            to_state = unquote(to_state)

            assert_receive(
              {:on_transition, ^fsm_name, ^to_state, payload},
              Finitomata.ExUnit.assert_receive_timeout()
            )

            unquote(ast)
          end

        :__timer_event__ ->
          quote generated: true, location: :keep do
            payload = :sys.get_state(fsm_name).payload
            unquote(ast)
          end

        _ ->
          quote generated: true, location: :keep do
            to_state = unquote(to_state)
            payload = Keyword.get(unquote(matches), to_state)
            unquote(ast)
          end
      end

    quote generated: true, location: :keep do
      unquote(transition_ast)
      unquote(action_ast)
    end
  end

  if Version.compare(System.version(), "1.16.0") == :lt do
    defp format_assertion(line, file, [content | _]) do
      format_assertion(line, file, content)
    end

    defp format_assertion(line, _file, content) do
      "clauses in a call to `assert_transition/5` must be either `:ok`, or `payload.inner.struct ~> match`, given:\n" <>
        Exception.format_snippet(%{content: content, offset: 0}, line)
    end
  else
    defp format_assertion(line, file, content) do
      Exception.format_snippet(
        {line, 1},
        {line + 1, 1},
        "clauses in a call to `assert_transition/5` must be either `:ok`, or `payload.inner.struct ~> match`, given:\n",
        file,
        content,
        "⇑ unexpected clause",
        ""
      )
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
    {entry, block} = Enum.split_with(block, &match?({:->, _, [[:*] | _]}, &1))

    quote generated: true, location: :keep do
      test unquote(test_name), unquote(ctx) = ctx do
        debug =
          Map.get(ctx, :ex_unit_debug, Application.get_env(:finitomata, :ex_unit_debug, false))

        if debug == true or (is_list(debug) and ctx.test in debug) or ctx.test == debug do
          require Logger
          [ctx.test, inspect(ctx)] |> Enum.join(" (context):\n") |> Logger.notice()
        end

        {fsm, matches} =
          case ctx do
            %{finitomata: %{fsm: fsm, auto_init_msgs: matches}} ->
              {fsm, matches}

            other ->
              raise TestTransitionError,
                message:
                  "in order to use `test_path/3` one should declare _FSM_ in `setup_finitomata/1` callback"
          end

        test_path_transitions(fsm.id, fsm.implementation, fsm.name, matches, do: unquote(entry))
        test_path_transitions(fsm.id, fsm.implementation, fsm.name, nil, do: unquote(block))
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
  defmacro test_path_transitions(id, impl, name, matches \\ nil, do: block) do
    block
    |> unblock()
    |> Enum.flat_map(fn
      {:->, _meta, [[event_payload], state_assertions]} ->
        state_assertions_ast = parse_assert_state_block(state_assertions)

        matches =
          case event_payload do
            :* ->
              matches

            :_ ->
              :__timer_event__

            _ ->
              _ =
                matches &&
                  Logger.warning(
                    "Unexpected matches with transition event [" <>
                      inspect(event_payload) <> "]: " <> inspect(matches)
                  )

              nil
          end

        [
          {event_payload,
           do_assert_transition(id, impl, name, event_payload, __CALLER__, matches,
             do: state_assertions_ast
           )}
        ]
    end)
  end

  defp parse_assert_state_block(block) do
    block
    |> unblock()
    |> Enum.map(&do_parse_assert_state_block/1)
  end

  defp do_parse_assert_state_block({:assert_state, meta, [state]}),
    do: {:->, meta, [[state], {:__block__, meta, []}]}

  defp do_parse_assert_state_block({:assert_state, meta, [state, [do: block]]}),
    do: {:->, meta, [[state], {:__block__, meta, unblock(block)}]}

  defp event_name({event, _payload}) when is_atom(event), do: event
  defp event_name(event) when is_atom(event), do: event

  defp unblock([{:__block__, _, block}]), do: unblock(block)
  defp unblock({:__block__, _, block}), do: unblock(block)
  defp unblock(block), do: List.wrap(block)

  defp do_handle_matches(ast, loop? \\ false)
  defp do_handle_matches([], _), do: []

  defp do_handle_matches({:when, _, [{:~>, _meta, [_var, _match_ast]}, _guard]} = guard, loop?),
    do: do_handle_matches([guard], loop?)

  defp do_handle_matches(
         [{:when, guard_meta, [{:~>, meta, [var, match_ast]}, guard]} | more],
         loop?
       ) do
    do_handle_matches([{:~>, meta, [var, {:when, guard_meta, [match_ast, guard]}]} | more], loop?)
  end

  defp do_handle_matches([{:->, meta, [[{_, _, _} = var], match_ast]} | more], loop?),
    do: do_handle_matches([{:~>, meta, [var, match_ast]} | more], loop?)

  defp do_handle_matches([{:~>, _meta, [{_, _, _} = var, match_ast]} | more], loop?) do
    path = var |> estructura_path() |> Enum.reverse()
    match = do_handle_matches_with_guards(match_ast, path)

    [match | do_handle_matches(more, loop?)]
  end

  defp do_handle_matches(any, false),
    do: any |> unblock() |> do_handle_matches(true)

  defp do_handle_matches(any, true),
    do: raise(Finitomata.TestSyntaxError, code: Macro.to_string(any))

  if Version.compare(System.version(), "1.18.0-rc.0") == :lt do
    defp do_handle_matches_with_guards(match_ast) do
      quote do
        if not is_nil(payload), do: assert(unquote(match_ast) = payload)
      end
    end

    defp do_handle_matches_with_guards(match_ast, path) do
      quote do
        assert unquote(match_ast) = get_in(payload, unquote(path))
      end
    end
  else
    defp do_handle_matches_with_guards(match_ast) do
      case match_ast do
        {:when, _, _} ->
          quote do
            if not is_nil(payload), do: assert(match?(unquote(match_ast), payload))
          end

        _no_guards ->
          quote do
            if not is_nil(payload), do: assert(unquote(match_ast) = payload)
          end
      end
    end

    defp do_handle_matches_with_guards(match_ast, path) do
      case match_ast do
        {:when, _, _} ->
          quote do
            assert match?(unquote(match_ast), get_in(payload, unquote(path)))
          end

        _no_guards ->
          quote do
            assert unquote(match_ast) = get_in(payload, unquote(path))
          end
      end
    end
  end
end
