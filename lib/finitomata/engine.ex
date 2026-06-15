defmodule Finitomata.Engine do
  @moduledoc false

  # Shared, process-agnostic runtime helpers used by every `use Finitomata` instance.
  #
  # Historically the whole FSM runtime was generated verbatim into each consuming module
  #   by the `use Finitomata` macro. That made the generated code huge, hard to test, and
  #   produced stacktraces pointing into macro-generated functions. This module is the seam
  #   for moving that logic into a single shared, directly unit-testable place.
  #
  # The functions here run *inside* the FSM process (they are ordinary function calls, not a
  #   separate server), therefore `self()` and the process dictionary still refer to the FSM
  #   itself. The transition orchestration (`transit/3`, `fork/3`, `maybe_store/7`,
  #   `maybe_pubsub/3`) and the stateless helpers live here; each FSM module keeps only thin
  #   delegations plus the per-module `telemetria`-instrumented `safe_on_*` callbacks that the
  #   Engine calls back into via the passed-in `module`. `init/1`, the `GenServer` callback
  #   shells, and the compile-time FSM setup remain generated, as they are coupled to
  #   compile-time configuration.

  require Logger

  alias Finitomata.{State, Transition}

  @typedoc "An entry of the bounded state history; consecutive re-entries collapse into a tuple"
  @type history_entry :: Transition.state() | {Transition.state(), pos_integer()}

  @doc """
  Normalizes an auto-driven event payload into a map carrying a `__retries__` counter,
  incrementing it on every pass.

  This is used for the transitions `Finitomata` drives itself (the initial entry transition,
  `hard`/banged transitions, and `ensure_entry` retries). A non-map payload `p` becomes
  `%{payload: p, __retries__: n}`. See `c:Finitomata.on_transition/4`.

      iex> Finitomata.Engine.event_payload(:go)
      {:go, %{__retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, %{foo: :bar}})
      {:go, %{foo: :bar, __retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, 42})
      {:go, %{payload: 42, __retries__: 1}}
      iex> Finitomata.Engine.event_payload({:go, %{__retries__: 2}})
      {:go, %{__retries__: 3}}
  """
  @spec event_payload(Transition.event() | {Transition.event(), Finitomata.event_payload()}) ::
          {Transition.event(), Finitomata.event_payload()}
  def event_payload({event, %{} = payload}),
    do: {event, Map.update(payload, :__retries__, 1, &(&1 + 1))}

  def event_payload({event, payload}),
    do: event_payload({event, %{payload: payload}})

  def event_payload(event),
    do: event_payload({event, %{}})

  @doc """
  Prepends `current` to the bounded `history`, collapsing consecutive re-entries of the
  same state into a `{state, count}` tuple, and caps the result at
  `Finitomata.State.history_size/0`.

      iex> Finitomata.Engine.history(:a, [])
      [:a]
      iex> Finitomata.Engine.history(:a, [:a])
      [{:a, 2}]
      iex> Finitomata.Engine.history(:a, [{:a, 2}])
      [{:a, 3}]
      iex> Finitomata.Engine.history(:a, [:b])
      [:a, :b]
  """
  @spec history(Transition.state(), [history_entry()]) :: [history_entry()]
  def history(current, history) do
    history
    |> case do
      [^current | rest] -> [{current, 2} | rest]
      [{^current, count} | rest] -> [{current, count + 1} | rest]
      _ -> [current | history]
    end
    |> Enum.take(State.history_size())
  end

  @doc false
  @spec safe_cancel_timer(false | {nil | reference(), pos_integer()}) ::
          false | {nil, pos_integer()}
  def safe_cancel_timer({ref, timer}) when is_integer(timer) and timer > 0 do
    _ = if is_reference(ref), do: Process.cancel_timer(ref, async: true, info: false)
    {nil, timer}
  end

  def safe_cancel_timer(_false), do: false

  @doc false
  @spec safe_init_timer(false | {nil | reference(), pos_integer()}) ::
          false | {reference(), pos_integer()}
  def safe_init_timer(timer) do
    case safe_cancel_timer(timer) do
      {nil, timer} when is_integer(timer) and timer > 0 ->
        {Process.send_after(self(), :on_timer, timer), timer}

      _ ->
        false
    end
  end

  @doc false
  @spec hibernate_noreply(State.t()) ::
          {:noreply, State.t()} | {:noreply, State.t(), :hibernate}
  def hibernate_noreply(%State{} = state) do
    if hibernate?(state), do: {:noreply, state, :hibernate}, else: {:noreply, state}
  end

  @doc false
  @spec hibernate_reply(term(), State.t()) ::
          {:reply, term(), State.t()} | {:reply, term(), State.t(), :hibernate}
  def hibernate_reply(reply, %State{} = state) do
    if hibernate?(state), do: {:reply, reply, state, :hibernate}, else: {:reply, reply, state}
  end

  # Decides whether the FSM should hibernate after settling in `state.current`. The
  #   `hibernate:` option may be `false` (never), `true` (always), a single `state()`, or a
  #   `[state()]`; the latter two hibernate only when the FSM rests in (one of) those states.
  #   `true`/`false` are atoms, hence the clause order below matters.
  @spec hibernate?(State.t()) :: boolean()
  defp hibernate?(%State{hibernate: false}), do: false
  defp hibernate?(%State{hibernate: true}), do: true

  defp hibernate?(%State{hibernate: states, current: current}) when is_list(states),
    do: current in states

  defp hibernate?(%State{hibernate: state, current: current}), do: current == state

  @doc false
  @spec transit(module(), {Transition.event(), Finitomata.event_payload()}, State.t()) ::
          {:noreply, State.t()}
          | {:noreply, State.t(), :hibernate}
          | {:stop, :normal, State.t()}
  def transit(module, {event, payload}, %State{} = state) do
    fsm = module.__config__(:fsm)

    with {:responds, true} <- {:responds, Transition.responds?(fsm, state.current, event)},
         {:on_exit, :ok} <- {:on_exit, module.safe_on_exit(state.current, state)},
         {:ok, new_current, new_payload} <-
           module.safe_on_transition(state.name, state.current, event, payload, state.payload),
         {:allowed, true, _} <-
           {:allowed, Transition.allowed?(fsm, state.current, new_current), new_current},
         # the target is valid — only now commit the persistency/listener side effects
         stored =
           maybe_store(
             module,
             {:ok, new_current, new_payload},
             state.name,
             state.current,
             event,
             payload,
             state.payload
           ),
         {:ok, new_current, new_payload} <- stored,
         _ = maybe_pubsub(module, stored, state.name),
         new_timer = safe_cancel_timer(state.timer),
         new_history = history(state.current, state.history),
         state = %{
           state
           | payload: new_payload,
             current: new_current,
             history: new_history,
             timer: safe_init_timer(new_timer)
         },
         {:on_enter, :ok} <- {:on_enter, module.safe_on_enter(new_current, state)} do
      if module.__config__(:cache_state),
        do: Finitomata.StateCache.put(state.finitomata_id, state.name, state.payload)

      cond do
        new_current == :* ->
          {:stop, :normal, state}

        new_current in module.__config__(:hard_states) ->
          {:noreply, state,
           {:continue, {:transition, event_payload(module.__config__(:hard)[new_current].event)}}}

        new_current in module.__config__(:fork_states) ->
          {:noreply, state, {:continue, {:fork, new_current}}}

        true ->
          hibernate_noreply(state)
      end
    else
      {:allowed, false, rejected} ->
        # `on_transition/4` resolved to a state that is not reachable from the current one;
        #   persistency/listener were not committed, so let the consumer roll back its own
        #   side effects before we keep the FSM in place.
        state = %{
          state
          | last_error:
              Finitomata.Error.wrap({:error, {:not_allowed, state.current, rejected}},
                state: state.current,
                event: event,
                event_payload: payload
              )
        }

        Logger.warning(
          "[⚐ ↹] transition from #{state.current} with #{event} to #{rejected} is not allowed; rolling back"
        )

        safe_on_rollback(module, event, payload, state)
        module.safe_on_failure(event, payload, state)
        hibernate_noreply(state)

      {err, false} ->
        Logger.warning(
          "[⚐ ↹] transition from #{state.current} with #{event} does not exists or not allowed (:#{err})"
        )

        module.safe_on_failure(event, payload, state)
        hibernate_noreply(state)

      {err, :ok} ->
        Logger.warning("[⚐ ↹] callback failed to return `:ok` (:#{err})")
        module.safe_on_failure(event, payload, state)
        hibernate_noreply(state)

      err ->
        state = %{
          state
          | last_error:
              Finitomata.Error.wrap(err,
                state: state.current,
                event: event,
                event_payload: payload
              )
        }

        cond do
          event in module.__config__(:soft_events) ->
            Logger.debug("[⚐ ↹] transition softly failed " <> inspect(err))
            hibernate_noreply(state)

          fsm
          |> Transition.allowed(state.current, event)
          |> Enum.all?(&(&1 in module.__config__(:ensure_entry))) ->
            {:noreply, state, {:continue, {:transition, event_payload({event, payload})}}}

          true ->
            Logger.warning("[⚐ ↹] transition failed " <> inspect(err))
            module.safe_on_failure(event, payload, state)
            hibernate_noreply(state)
        end
    end
  end

  @doc false
  @spec fork(module(), Transition.state(), State.t()) ::
          {:noreply, State.t()} | {:noreply, State.t(), :hibernate}
  def fork(module, fork_state, %State{} = state) do
    fork_data =
      case state.payload do
        %{fork_data: %{} = fork_data} -> fork_data
        _ -> %{}
      end

    {object, fork_data} = Map.pop(fork_data, :object)
    {id, fork_data} = Map.pop(fork_data, :id)

    _ =
      module.__config__(:forks)
      |> Keyword.fetch!(fork_state)
      |> List.wrap()
      |> module.safe_on_fork(fork_state, state)
      |> case do
        {:ok, fork_impl, event} ->
          fsm_name = Finitomata.fsm_name(state)

          Finitomata.start_fsm(
            state.finitomata_id,
            fork_impl,
            {:fork, fork_state, fsm_name},
            %{
              owner: %{
                event: event,
                id: state.finitomata_id,
                name: fsm_name,
                pid: Finitomata.pid(state)
              },
              history: %{current: 0, steps: []},
              steps: %{passed: 0, left: Transition.steps_handled(fork_impl.__config__(:fsm))},
              object: object,
              id: id,
              data: fork_data
            }
          )

        {:error, error} ->
          Logger.warning("[⚐ ↹] fork from #{fork_state} failed (#{inspect(error)})")
          maybe_pubsub_fork_error(module, state.name, fork_state, error)
      end

    hibernate_noreply(state)
  end

  @doc false
  @spec maybe_store(
          module(),
          Finitomata.transition_resolution(),
          Finitomata.fsm_name(),
          Transition.state(),
          Transition.event(),
          Finitomata.event_payload(),
          State.payload()
        ) :: Finitomata.transition_resolution()
  def maybe_store(module, result, name, current, event, event_payload, state_payload) do
    case module.__config__(:persistency) do
      nil ->
        result

      persistency ->
        do_maybe_store(persistency, result, name, current, event, event_payload, state_payload)
    end
  end

  defp do_maybe_store(
         persistency,
         {:error, reason},
         name,
         current,
         event,
         event_payload,
         state_payload
       ) do
    with true <- function_exported?(persistency, :store_error, 4),
         info = %{
           from: current,
           to: nil,
           event: event,
           event_payload: event_payload,
           object: state_payload
         },
         {:error, persistency_error_reason} <-
           persistency.store_error(name, state_payload, reason, info) do
      {:error, transition: reason, persistency: persistency_error_reason}
    else
      _ -> {:error, transition: reason}
    end
  end

  defp do_maybe_store(
         persistency,
         {:ok, new_state, new_state_payload} = result,
         name,
         current,
         event,
         event_payload,
         state_payload
       ) do
    info = %{
      from: current,
      to: new_state,
      event: event,
      event_payload: event_payload,
      object: state_payload
    }

    name
    |> persistency.store(new_state_payload, info)
    |> case do
      :ok -> result
      {:ok, updated_state_payload} -> {:ok, new_state, updated_state_payload}
      {:error, reason} -> {:error, persistency: reason}
    end
  end

  defp do_maybe_store(
         _persistency,
         result,
         _name,
         _current,
         _event,
         _event_payload,
         _state_payload
       ),
       do: {:error, transition: result}

  @doc false
  @spec maybe_pubsub(module(), Finitomata.transition_resolution(), Finitomata.fsm_name()) :: :ok
  def maybe_pubsub(module, result, name),
    do: do_maybe_pubsub(module.__config__(:listener), result, name)

  defp do_maybe_pubsub(nil, _result, _name), do: :ok

  defp do_maybe_pubsub(listener, {:ok, state, payload}, name) do
    cond do
      is_atom(listener) and function_exported?(listener, :after_transition, 3) ->
        with some when some != :ok <- listener.after_transition(name, state, payload) do
          Logger.warning(
            "[♻️] Listener ‹" <>
              inspect(Function.capture(listener, :after_transition, 3)) <>
              "› returned unexpected ‹" <>
              inspect(some) <>
              "› when called with ‹" <> inspect([name, state, payload]) <> "›"
          )
        end

        :ok

      is_pid(listener) or is_port(listener) or is_atom(listener) or is_tuple(listener) ->
        send(listener, {:finitomata, {:transition, state, payload}})
        :ok

      true ->
        :ok
    end
  end

  defp do_maybe_pubsub(_listener, _result, _name), do: :ok

  @doc false
  @spec maybe_pubsub_fork_error(module(), Finitomata.fsm_name(), Transition.state(), any()) :: :ok
  def maybe_pubsub_fork_error(module, name, fork_state, error),
    do: do_maybe_pubsub_fork_error(module.__config__(:listener), name, fork_state, error)

  defp do_maybe_pubsub_fork_error(nil, _name, _fork_state, _error), do: :ok

  defp do_maybe_pubsub_fork_error(listener, name, fork_state, error) do
    cond do
      is_atom(listener) and function_exported?(listener, :after_transition, 3) ->
        notify_fork_failure(listener, name, fork_state, error)

      is_pid(listener) or is_port(listener) or is_atom(listener) or is_tuple(listener) ->
        send(listener, {:finitomata, {:fork_error, fork_state, error}})
        :ok

      true ->
        :ok
    end
  end

  # `listener` is a `Finitomata.Listener` behaviour module; `after_fork_failure/3` is optional,
  #   so notify only when it is implemented, otherwise stay silent (do not message the module).
  defp notify_fork_failure(listener, name, fork_state, error) do
    if function_exported?(listener, :after_fork_failure, 3) do
      with some when some != :ok <- listener.after_fork_failure(name, fork_state, error) do
        Logger.warning(
          "[♻️] Listener ‹" <>
            inspect(Function.capture(listener, :after_fork_failure, 3)) <>
            "› returned unexpected ‹" <>
            inspect(some) <>
            "› when called with ‹" <> inspect([name, fork_state, error]) <> "›"
        )
      end
    end

    :ok
  end

  @doc false
  @spec handle_call(module(), term(), State.t()) ::
          {:reply, term(), State.t()} | {:reply, term(), State.t(), :hibernate}
  def handle_call(_module, :state, %State{} = state), do: hibernate_reply(state, state)

  def handle_call(_module, {:state, fun}, %State{} = state) when is_function(fun, 1),
    do: hibernate_reply(fun.(state), state)

  def handle_call(_module, :current_state, %State{} = state),
    do: hibernate_reply(state.current, state)

  def handle_call(_module, :name, %State{} = state),
    do: hibernate_reply(State.human_readable_name(state, false), state)

  def handle_call(module, {:allowed?, to}, %State{} = state),
    do: hibernate_reply(Transition.allowed?(module.__config__(:fsm), state.current, to), state)

  def handle_call(module, {:responds?, event}, %State{} = state),
    do:
      hibernate_reply(Transition.responds?(module.__config__(:fsm), state.current, event), state)

  def handle_call(_module, whatever, %State{} = state) do
    Logger.error(
      "Unexpected `GenServer.call/2` with a message ‹#{inspect(whatever)}›. " <>
        "`Finitomata` does not accept direct calls. Please use `on_transition/4` callback instead."
    )

    hibernate_reply(:not_allowed, state)
  end

  @doc false
  @spec handle_cast(module(), term(), State.t()) ::
          {:noreply, State.t()}
          | {:noreply, State.t(), :hibernate}
          | {:noreply, State.t(), {:continue, term()}}
  def handle_cast(_module, {:reset_timer, tick?, _new_value}, %State{} = state) do
    timer =
      if tick? do
        _ = safe_cancel_timer(state.timer)
        :ok = Process.send(self(), :on_timer, [])
        state.timer
      else
        safe_init_timer(state.timer)
      end

    hibernate_noreply(%{state | timer: timer})
  end

  def handle_cast(_module, {event, payload}, %State{} = state),
    do: {:noreply, state, {:continue, {:transition, {event, payload}}}}

  def handle_cast(_module, whatever, %State{} = state) do
    Logger.error(
      "Unexpected `GenServer.cast/2` with a message ‹#{inspect(whatever)}›. " <>
        "`Finitomata` does not accept direct casts. Please use `on_transition/4` callback instead."
    )

    hibernate_noreply(state)
  end

  @doc false
  @spec handle_continue(module(), term(), State.t()) ::
          {:noreply, State.t()}
          | {:noreply, State.t(), :hibernate}
          | {:stop, :normal, State.t()}
  def handle_continue(module, {:transition, {event, payload}}, %State{} = state),
    do: transit(module, {event, payload}, state)

  def handle_continue(module, {:fork, fork_state}, %State{} = state),
    do: fork(module, fork_state, state)

  @doc false
  @spec terminate(module(), term(), State.t()) :: term()
  def terminate(module, _reason, %State{} = state) do
    if module.__config__(:cache_state),
      do: Finitomata.StateCache.delete(state.finitomata_id, state.name)

    module.safe_on_terminate(state)
  end

  @doc false
  @spec handle_info(module(), term(), State.t()) ::
          {:noreply, State.t()} | {:noreply, State.t(), :hibernate}
  def handle_info(_module, whatever, %State{} = state)
      when not is_tuple(state.timer) or not is_integer(elem(state.timer, 1)) or
             whatever != :on_timer do
    Logger.error(
      "Unexpected message ‹#{inspect(whatever)}› received by #{inspect(State.human_readable_name(state))}. " <>
        "`Finitomata` does not accept direct messages. Please use `on_transition/4` callback instead."
    )

    hibernate_noreply(state)
  end

  def handle_info(module, :on_timer, %State{} = state) do
    if module.__config__(:timer),
      do: do_on_timer(module, state),
      else: on_timer_undeclared(state)
  end

  defp on_timer_undeclared(%State{} = state) do
    Logger.warning("[⚑ ↹] on_timer message received, but no `on_timer/2` callback is declared")
    hibernate_noreply(state)
  end

  defp do_on_timer(module, %State{} = state) do
    state.current
    |> module.safe_on_timer(state)
    |> case do
      :ok ->
        hibernate_noreply(state)

      {:ok, state_payload} ->
        if module.__config__(:cache_state),
          do: Finitomata.StateCache.put(state.finitomata_id, state.name, state_payload)

        hibernate_noreply(%{state | payload: state_payload})

      {:transition, {event, event_payload}, state_payload} ->
        transit(module, {event, event_payload}, %{state | payload: state_payload})

      {:transition, event, state_payload} ->
        transit(module, {event, nil}, %{state | payload: state_payload})

      {:reschedule, value} ->
        timer = with {ref, _old_value} <- state.timer, do: {ref, value}
        hibernate_noreply(%{state | timer: timer})

      weird ->
        Logger.warning("[⚑ ↹] on_timer returned a garbage " <> inspect(weird))
        hibernate_noreply(state)
    end
    |> then(fn
      {:noreply, %State{timer: timer} = state} ->
        hibernate_noreply(%{state | timer: safe_init_timer(timer)})

      other ->
        other
    end)
  end

  @doc false
  @spec init(module(), map()) ::
          {:ok, State.t()} | {:ok, State.t(), {:continue, term()}} | {:stop, keyword()}
  def init(
        module,
        %{
          finitomata_id: id,
          name: name,
          parent: parent,
          payload: payload,
          with_persistency: persistency
        } = state
      )
      when not is_nil(name) and not is_nil(persistency) do
    {lifecycle, {state, payload}} =
      case payload do
        mod when is_atom(mod) ->
          persistency.load({payload, id: name})

        %struct{} = payload ->
          persistency.load({struct, payload |> Map.from_struct() |> Map.put_new(:id, name)})

        %{type: type, id: id} ->
          persistency.load({type, %{id => name}})

        other ->
          Logger.warning(
            "Loading from persisted for ‹#{inspect(state)}› failed; wrong payload: " <>
              inspect(other)
          )

          {:failed, {nil, other}}
      end

    init(module, %{
      name: name,
      finitomata_id: id,
      parent: parent,
      state: state,
      payload: payload,
      lifecycle: lifecycle,
      persistency: persistency
    })
  end

  def init(module, %{payload: payload} = init_arg) do
    lifecycle = Map.get(init_arg, :lifecycle, :unknown)
    {state, init_arg} = Map.pop(init_arg, :state)

    init_state =
      if is_nil(state) or lifecycle in [:failed, :created] do
        init_arg
        |> module.safe_on_start(payload)
        |> case do
          {:stop, reason} -> {:stop, :on_start, reason}
          {:ok, payload} -> {nil, payload}
          {:continue, payload} -> {nil, payload}
          _ -> {nil, payload}
        end
      else
        {state, payload}
      end

    do_init(module, init_state, init_arg)
  end

  @spec do_init(module(), tuple(), map()) ::
          {:ok, State.t()} | {:ok, State.t(), {:continue, term()}} | {:stop, keyword()}
  defp do_init(_module, {:stop, :on_start, reason}, init_arg),
    do: {:stop, reason: reason, init_arg: init_arg}

  defp do_init(
         module,
         {state, payload},
         %{finitomata_id: id, name: name, parent: parent} = init_arg
       ) do
    lifecycle = Map.get(init_arg, :lifecycle, :unknown)
    timer = safe_init_timer({nil, module.__config__(:timer)})

    state =
      %State{
        name: name,
        finitomata_id: id,
        parent: parent,
        lifecycle: lifecycle,
        persistency: Map.get(init_arg, :persistency, nil),
        timer: timer,
        cache_state: module.__config__(:cache_state),
        hibernate: module.__config__(:hibernate),
        payload: payload
      }
      |> put_current_state_if_loaded(lifecycle, state)

    if module.__config__(:cache_state),
      do: Finitomata.StateCache.put(state.finitomata_id, state.name, state.payload)

    if lifecycle == :loaded,
      do: {:ok, state},
      else:
        {:ok, state, {:continue, {:transition, event_payload({module.__config__(:entry), nil})}}}
  end

  defp put_current_state_if_loaded(state, :loaded, fsm_state)
       when not is_nil(fsm_state),
       do: Map.put(state, :current, fsm_state)

  defp put_current_state_if_loaded(state, _, _fsm_state), do: state

  # Per-callback wrappers. Each generated FSM module keeps a thin, `@telemetria`-annotated
  #   `safe_on_*` shim (so telemetry events stay grouped by the consumer module) that
  #   delegates here. Centralizing the bodies keeps the `use Finitomata` quote small while
  #   preserving the exact callback-resolution, error-wrapping, and return semantics.

  @doc false
  @spec safe_on_start(module(), :loaded | map(), State.payload()) ::
          {:stop, term()} | {:continue, State.payload()} | {:ok, State.payload()} | :ignore
  def safe_on_start(_module, :loaded, payload), do: {:ok, payload}

  def safe_on_start(module, _state, payload) do
    if function_exported?(module, :on_start, 1),
      do: module.on_start(payload),
      else: :ignore
  rescue
    err ->
      _ = report_error(err, __STACKTRACE__, "on_start/1")
      {:stop, err}
  end

  @doc false
  @spec safe_on_transition(
          module(),
          Finitomata.fsm_name(),
          Transition.state(),
          Transition.event(),
          Finitomata.event_payload(),
          State.payload()
        ) :: Finitomata.transition_resolution() | {:error, :on_transition_raised}
  # A *successful* resolution is returned verbatim: persisting it (`store`) and notifying the
  #   listener (`after_transition`) is deferred to `transit/3`, which only commits them once
  #   the resolved target has passed the `:allowed?` guard — so a rejected transition never
  #   reaches the storage or the listener. A *failed* resolution is still persisted here via
  #   `store_error/4` (when a persistency is configured), preserving the historic behaviour.
  def safe_on_transition(module, name, current, event, event_payload, state_payload) do
    case module.on_transition(current, event, event_payload, state_payload) do
      {:ok, _new_current, _new_payload} = ok ->
        ok

      other ->
        maybe_store(module, other, name, current, event, event_payload, state_payload)
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_transition/4")
  end

  @doc false
  @spec safe_on_fork(module(), [module()], Transition.state(), State.t()) ::
          {:ok, module(), Transition.event()} | {:error, any()}
  def safe_on_fork(module, forks, fork_state, state) do
    cond do
      function_exported?(module, :on_fork, 2) ->
        case module.on_fork(fork_state, state.payload) do
          {:ok, fork_impl} ->
            case Enum.find(forks, &match?({_event, ^fork_impl}, &1)) do
              nil -> {:error, :unknown_fork_resolution}
              {event, ^fork_impl} -> {:ok, fork_impl, event}
            end

          :ok ->
            case forks do
              [{event, fork_impl}] -> {:ok, fork_impl, event}
              [] -> {:error, :missing_fork_resolution}
              _ -> {:error, :multiple_fork_resolutions}
            end

          _other ->
            {:error, :bad_fork_resolution}
        end

      match?([_fork], forks) ->
        [{event, fork_impl}] = forks
        {:ok, fork_impl, event}

      true ->
        {:error, :missing_fork_resolution}
    end
  rescue
    err ->
      _ = report_error(err, __STACKTRACE__, "on_fork/2")
      {:error, :on_fork_raised}
  end

  @doc false
  @spec safe_on_failure(module(), Transition.event(), Finitomata.event_payload(), State.t()) ::
          :ok
  def safe_on_failure(module, event, event_payload, state_payload) do
    if function_exported?(module, :on_failure, 3) do
      with other when other != :ok <-
             module.on_failure(event, event_payload, state_payload) do
        Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
        :ok
      end
    else
      :ok
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_failure/3")
  end

  @doc false
  @spec safe_on_rollback(module(), Transition.event(), Finitomata.event_payload(), State.t()) ::
          :ok
  def safe_on_rollback(module, event, event_payload, state_payload) do
    if function_exported?(module, :on_rollback, 3) do
      with other when other != :ok <-
             module.on_rollback(event, event_payload, state_payload) do
        Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
        :ok
      end
    else
      :ok
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_rollback/3")
  end

  @doc false
  @spec safe_on_enter(module(), Transition.state(), State.t()) :: :ok
  def safe_on_enter(module, state, state_payload) do
    if function_exported?(module, :on_enter, 2) do
      with other when other != :ok <- module.on_enter(state, state_payload) do
        Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
        :ok
      end
    else
      :ok
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_enter/2")
  end

  @doc false
  @spec safe_on_exit(module(), Transition.state(), State.t()) :: :ok
  def safe_on_exit(module, state, state_payload) do
    if function_exported?(module, :on_exit, 2) do
      with other when other != :ok <- module.on_exit(state, state_payload) do
        Logger.info("[♻️] Unexpected return from a callback [#{inspect(other)}], must be :ok")
        :ok
      end
    else
      :ok
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_exit/2")
  end

  @doc false
  @spec safe_on_terminate(module(), State.t()) :: :ok
  def safe_on_terminate(module, state) do
    if function_exported?(module, :on_terminate, 1) do
      with other when other != :ok <- module.on_terminate(state) do
        Logger.warning(
          "[♻️] Unexpected return from `on_terminate/1` [#{inspect(other)}], must be :ok"
        )
      end
    else
      :ok
    end
  rescue
    err -> report_error(err, __STACKTRACE__, "on_terminate/1")
  end

  @doc false
  @spec safe_on_timer(module(), Transition.state(), State.t()) ::
          :ok
          | {:ok, State.t()}
          | {:transition, {Transition.state(), Finitomata.event_payload()}, State.payload()}
          | {:transition, Transition.state(), State.payload()}
          | {:reschedule, pos_integer()}
  def safe_on_timer(module, state, state_payload) do
    if function_exported?(module, :on_timer, 2),
      do: module.on_timer(state, state_payload),
      else: :ok
  rescue
    err -> report_error(err, __STACKTRACE__, "on_timer/2")
  end

  @spec report_error(term(), Exception.stacktrace(), String.t()) :: {:error, term()}
  defp report_error(err, stacktrace, from) do
    case err do
      %{__exception__: true} ->
        {ex, st} = Exception.blame(:error, err, stacktrace)
        Logger.warning(Exception.format(:error, ex, st))
        {:error, Exception.message(err)}

      _ ->
        Logger.warning("[⚑ ↹] #{from} raised: " <> inspect(err) <> "\n" <> inspect(stacktrace))

        {:error, :on_transition_raised}
    end
  end
end
