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
  @spec safe_cancel_timer(false | {reference(), pos_integer()}) ::
          false | {nil, pos_integer()}
  def safe_cancel_timer({ref, timer}) when is_integer(timer) and timer > 0 do
    if is_reference(ref), do: Process.cancel_timer(ref, async: true, info: false)
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
  def hibernate_noreply(%State{hibernate: false} = state), do: {:noreply, state}
  def hibernate_noreply(%State{} = state), do: {:noreply, state, :hibernate}

  @doc false
  @spec hibernate_reply(term(), State.t()) ::
          {:reply, term(), State.t()} | {:reply, term(), State.t(), :hibernate}
  def hibernate_reply(reply, %State{hibernate: false} = state), do: {:reply, reply, state}
  def hibernate_reply(reply, %State{} = state), do: {:reply, reply, state, :hibernate}

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
         new_timer <- safe_cancel_timer(state.timer),
         {:allowed, true} <- {:allowed, Transition.allowed?(fsm, state.current, new_current)},
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
end
