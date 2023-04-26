defmodule Finitomata.Hook do
  @moduledoc false

  alias Finitomata.Mix.Events

  @type ast_meta :: keyword()
  @type ast_tuple :: {atom(), ast_meta(), any()}
  @type t :: %{
          __struct__: __MODULE__,
          env: Macro.Env.t(),
          module: module(),
          kind: :def | :defp,
          fun: atom(),
          arity: arity(),
          args: [ast_tuple()],
          guards: [ast_tuple()],
          body: [{:do, ast_tuple()}]
        }
  defstruct ~w|env module kind fun arity args guards body|a

  defimpl Inspect do
    @moduledoc false

    import Inspect.Algebra

    @spec inspect(Finitomata.Hook.t(), Inspect.Opts.t()) ::
            :doc_line
            | :doc_nil
            | binary
            | {:doc_collapse, pos_integer}
            | {:doc_force, any}
            | {:doc_break | :doc_color | :doc_cons | :doc_fits | :doc_group | :doc_string, any,
               any}
            | {:doc_nest, any, :cursor | :reset | non_neg_integer, :always | :break}
    def inspect(%Finitomata.Hook{module: module, fun: fun, args: args, guards: guards}, opts) do
      case Keyword.get(opts.custom_options, :fancy, true) do
        false ->
          inner = [module: module, fun: fun, args: args, guards: guards]
          concat(["#Finitomata.Hook<", to_doc(inner, opts), ">"])

        _ ->
          args = args |> Macro.to_string() |> String.slice(1..-2)

          guards =
            case guards do
              [] -> ""
              guards -> " when " <> (guards |> Macro.to_string() |> String.slice(1..-2))
            end

          concat([" ↹‹#{inspect(module)}.#{fun}(", args, ")", guards, "›"])
      end
    end
  end

  def __on_definition__(env, :def, :on_transition, [_, _, _, _] = args, guards, body) do
    if compiler?() do
      Events.put(
        :hooks,
        struct(__MODULE__,
          env: env,
          module: env.module,
          kind: :def,
          fun: :on_transition,
          arity: 4,
          args: args,
          guards: guards,
          body: body
        )
      )
    end
  end

  def __on_definition__(_env, _kind, _fun, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    if Code.ensure_loaded?(Mix) do
      deps? =
        [depth: 1]
        |> Mix.Project.deps_scms()
        |> Map.take([:finitomata, :siblings])
        |> map_size()
        |> Kernel.>(0)

      if not compiler?() and deps? do
        Mix.shell().info([
          [:bright, :yellow, "warning: ", :reset],
          "unhandled finitomata declaration found in ",
          [:bright, :blue, inspect(env.module), :reset],
          ",\n         but we were unable to analyse the correctness of the FSM.\n         Add ",
          [:bright, :cyan, ":finitomata", :reset],
          " compiler to ",
          [:bright, :cyan, "compilers:", :reset],
          " in your ",
          [:bright, :cyan, "mix.exs", :reset],
          "!\n  #{Path.relative_to_cwd(env.file)}:#{env.line}"
        ])
      end
    end

    quote generated: true,
          location: :keep,
          bind_quoted: [module: env.module, file: env.file, line: env.line] do
      states = @__config__[:states]

      @typedoc """
      Kind of event which might be send to initiate the transition.

      ## FSM representation

      ```#{@__config__[:syntax] |> Module.split() |> List.last() |> Macro.underscore()}
      #{@__config__[:syntax].lint(@__config__[:dsl])}
      ```
      """
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
          Logger.warning("[✗ ↹] " <> inspect(state: state, event: event, event_payload: payload))
        end
      end

      if :on_enter in @__config__[:impl_for] do
        @impl Finitomata
        def on_enter(entering, state) do
          Logger.debug("[← ↹] " <> inspect(state: state, entering: entering))
        end
      end

      if :on_exit in @__config__[:impl_for] do
        @impl Finitomata
        def on_exit(exiting, state) do
          Logger.debug("[→ ↹] " <> inspect(state: state, exiting: exiting))
        end
      end

      if :on_terminate in @__config__[:impl_for] do
        @impl Finitomata
        def on_terminate(state) do
          Logger.info("[◉ ↹] " <> inspect(state: state))
        end
      end

      if :on_timer in @__config__[:impl_for] do
        @impl Finitomata
        def on_timer(current_state, state) do
          Logger.debug("[✓ ↹] " <> inspect(current_state: current_state, state: state))
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

  @spec details(t()) :: [
          {:args, [ast_tuple()]} | {:body, [{:do, ast_tuple()}]} | {:guards, [ast_tuple()]}
        ]
  @doc false
  def details(%__MODULE__{args: args, guards: guards, body: body}),
    do: [args: args, guards: guards, body: body]

  @spec compiler? :: boolean()
  defp compiler? do
    Events
    |> Process.whereis()
    |> then(fn
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end)
  end
end
