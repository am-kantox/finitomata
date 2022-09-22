defmodule Finitomata.Hook do
  @moduledoc false

  @type ast_meta :: keyword()
  @type ast_tuple :: {atom(), ast_meta(), any()}
  @type info :: %{
          env: Macro.Env.t(),
          kind: :def | :defp,
          fun: atom(),
          arity: arity(),
          args: [ast_tuple()],
          guards: [ast_tuple()],
          body: [{:do, ast_tuple()}],
          payload: map()
        }
  defstruct ~w|env kind fun arity args guards body payload|a

  def __on_definition__(env, kind, :on_transition, args, guards, body) do
    Module.put_attribute(
      env.module,
      :finitomata_on_transition_clauses,
      struct(__MODULE__,
        env: env,
        kind: kind,
        fun: :on_transition,
        arity: length(args),
        args: args |> IO.inspect(label: "\nARGS"),
        guards: guards,
        body: body
      )
    )
  end

  def __on_definition__(_env, _kind, _fun, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    quote generated: true,
          location: :keep,
          bind_quoted: [module: env.module, file: env.file, line: env.line] do
      states = @__config__[:states]
      @type state :: unquote(Enum.reduce(states, &{:|, [], [&1, &2]}))

      if :on_transition in @__config__[:impl_for] do
        @impl Finitomata
        def on_transition(current, event, event_payload, state_payload) do
          Logger.debug(
            "[✓ ⇄] with: " <>
              inspect(
                current: current,
                event: event,
                event_payload: event_payload,
                state: state_payload
              )
          )

          case Finitomata.Transition.allowed(@__config__[:fsm], current, event) do
            [new_current] -> {:ok, new_current, state_payload}
            [] -> {:error, {:undefined_transition, {current, event}}}
            other -> {:error, {:ambiguous_transition, {current, event}, other}}
          end
        end
      end

      if :on_failure in @__config__[:impl_for] do
        @impl Finitomata
        def on_failure(event, payload, state) do
          Logger.warn("[✗ ⇄] " <> inspect(state: state, event: event, payload: payload))
        end
      end

      if :on_enter in @__config__[:impl_for] do
        @impl Finitomata
        def on_enter(entering, state) do
          Logger.debug("[← ⇄] " <> inspect(state: state, entering: entering))
        end
      end

      if :on_exit in @__config__[:impl_for] do
        @impl Finitomata
        def on_exit(exiting, state) do
          Logger.debug("[→ ⇄] " <> inspect(state: state, exiting: exiting))
        end
      end

      if :on_terminate in @__config__[:impl_for] do
        @impl Finitomata
        def on_terminate(state) do
          Logger.info("[◉ ⇄] " <> inspect(state: state))
        end
      end

      if :on_timer in @__config__[:impl_for] do
        @impl Finitomata
        def on_timer(current_state, state) do
          Logger.debug("[✓ ⇄] " <> inspect(current_state: current_state, state: state))
        end
      end

      if is_integer(@__config__[:timer]) and not Module.defines?(module, {:on_timer, 2}) do
        raise CompileError,
          file: Path.relative_to_cwd(file),
          line: line,
          description:
            "when `timer: non_neg_integer()` is given to `use Finitomata` " <>
              "there must be `on_timer/2` callback defined"
      end
    end
  end
end
