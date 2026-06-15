defmodule Finitomata.ConfigBuilder do
  @moduledoc false

  # Compile-time helpers that turn validated `use Finitomata` options into the compiled-in
  #   `@__config__` map (and the generated module's `@moduledoc`).
  #
  # This logic used to live inline in the `use Finitomata` quote (`Finitomata.ast/2`). The
  #   parsing is branchy but runs exactly once, at the consuming module's compile time, so
  #   pulling it out of the generated code keeps the quote small (within Credo's
  #   complexity/quote-length budgets) and makes the configuration directly unit-testable.
  #
  # Everything here executes in the compile-time context of the consuming module: `env` is
  #   that module's `__ENV__`, and side effects such as `Mox.defmock/2` define modules
  #   under `env.module`. The one value resolved by the caller and passed in is `timer`,
  #   because its `Application.compile_env/3` default must be captured in the consumer's
  #   context rather than this module's.

  alias Finitomata.Transition

  @impls ~w|on_transition on_failure on_fork on_enter on_exit on_start on_terminate on_timer|a

  @doc """
  Builds the compiled-in `@__config__` map from validated `use Finitomata` `options` in the
    compile-time context of `env`, with the already-resolved `timer` value.

  Returns `{config, telemetria_levels}`.
  """
  @spec build(keyword(), Macro.Env.t(), false | non_neg_integer()) :: {map(), keyword()}
  def build(options, env, timer) do
    reporter = if Code.ensure_loaded?(Mix), do: Mix.shell(), else: Logger

    syntax = syntax(Keyword.fetch!(options, :syntax), reporter)
    forks = Keyword.fetch!(options, :forks)
    auto_terminate = Keyword.fetch!(options, :auto_terminate)

    dsl = Keyword.fetch!(options, :fsm)
    fsm = parse_fsm(syntax, dsl, env)

    hard = hard(fsm, auto_terminate)
    soft = soft(fsm)

    config = %{
      syntax: syntax,
      fsm: fsm,
      dsl: dsl,
      impl_for: impl_for(Keyword.fetch!(options, :impl_for)),
      forks: forks,
      persistency: Keyword.fetch!(options, :persistency),
      listener:
        listener(
          Keyword.fetch!(options, :listener),
          Keyword.fetch!(options, :mox_envs),
          env,
          reporter
        ),
      auto_terminate: auto_terminate,
      hibernate: Keyword.fetch!(options, :hibernate),
      cache_state: Keyword.fetch!(options, :cache_state),
      ensure_entry: ensure_entry(Keyword.fetch!(options, :ensure_entry), fsm),
      states: Transition.states(fsm),
      events: Transition.events(fsm),
      paths: Transition.straight_paths(fsm),
      loops: Transition.loops(fsm),
      entry: Transition.entry(:transition, fsm).event,
      hard: hard,
      hard_states: Keyword.keys(hard),
      soft: soft,
      soft_events: Enum.map(soft, & &1.event),
      fork_states: Keyword.keys(forks),
      timer: timer
    }

    {config, telemetria_levels(Keyword.fetch!(options, :telemetria_levels))}
  end

  @doc """
  Builds the `@moduledoc` for the generated _FSM_ module from its `config`, appending the
    module's own `existing` `@moduledoc` (if any) after a horizontal rule.
  """
  @spec moduledoc(map(), term()) :: String.t()
  def moduledoc(config, existing) do
    own = if is_binary(existing), do: "\n---\n" <> existing, else: ""

    """
    The instance of _FSM_ backed up by `Finitomata`.

    - _entry event_ → `:#{config.entry}`
    - _forks_ → `#{if [] == config.forks, do: "✗", else: inspect(config.forks)}`
    - _persistency_ → `#{if config.persistency, do: inspect(config.persistency), else: "✗"}`
    - _listener_ → `#{if config.listener, do: inspect(config.listener), else: "✗"}`
    - _timer_ → `#{config.timer || "✗"}`
    - _hibernate_ → `#{config.hibernate || "✗"}`
    - _cache_state_ → `#{if config.cache_state, do: "✓", else: "✗"}`

    ## FSM representation

    ```#{config.syntax |> Module.split() |> List.last() |> Macro.underscore()}
    #{config.syntax.lint(config.dsl)}
    ```

    ### FSM paths

    ```elixir
    #{Enum.map_join(config.paths, "\n", &inspect/1)}
    ```

    ### FSM loops

    ```elixir
    #{if [] != config.loops, do: Enum.map_join(config.loops, "\n", &inspect/1), else: "no loops"}
    ```

    """ <> own
  end

  @spec telemetria_levels(:none | keyword()) :: keyword()
  defp telemetria_levels(:none), do: []

  defp telemetria_levels(some) do
    case Keyword.split(some, [:all]) do
      {[], levels} ->
        levels

      {[all: level], levels} ->
        [
          on_transition: level,
          on_failure: level,
          on_fork: level,
          on_enter: level,
          on_exit: level,
          on_start: level,
          on_terminate: level,
          on_timer: level
        ]
        |> Keyword.merge(levels)
    end
  end

  @spec syntax(atom(), module()) :: module()
  defp syntax(syntax, reporter) do
    if syntax in [Finitomata.Mermaid, Finitomata.PlantUML] do
      reporter.info([
        [:yellow, "deprecated: ", :reset],
        "using built-in modules as syntax names is deprecated, please use ",
        [:blue, ":flowchart", :reset],
        " and/or ",
        [:blue, ":state_diagram", :reset],
        " instead"
      ])
    end

    case syntax do
      :flowchart -> Finitomata.Mermaid
      :state_diagram -> Finitomata.PlantUML
      module when is_atom(module) -> module
    end
  end

  @spec listener(term(), atom() | [atom()], Macro.Env.t(), module()) :: term()
  defp listener(listener, mox_envs, env, reporter) do
    mox_envs = List.wrap(mox_envs)
    def_mock = fn -> def_mock(env, reporter) end

    case listener do
      :mox -> if Mix.env() in mox_envs, do: def_mock.()
      {:mox, listener} -> if Mix.env() in mox_envs, do: def_mock.(), else: listener
      {listener, :mox} -> if Mix.env() in mox_envs, do: def_mock.(), else: listener
      listener -> listener
    end
  end

  @spec def_mock(Macro.Env.t(), module()) :: module()
  case Code.ensure_compiled(Mox) do
    {:error, error} ->
      defp def_mock(_env, reporter) do
        reporter.info([
          [:yellow, "expectation: ", :reset],
          "to be able to use ",
          [:blue, ":mox", :reset],
          " listener in tests with ",
          [:blue, "`Finitomata.ExUnit`", :reset],
          ", please add ",
          [:blue, "`{:mox, \"~> 1.0\", only: [:test]}`", :reset],
          " as a dependency to your ",
          [:blue, "`mix.exs`", :reset],
          " project file (got: ",
          [:yellow, inspect(unquote(error)), :reset],
          ")"
        ])
      end

    {:module, _} ->
      defp def_mock(env, _reporter) do
        [env.module, Mox]
        |> Module.concat()
        |> tap(fn mox_mod ->
          Mox.defmock(mox_mod, for: Finitomata.Listener)
          Code.ensure_compiled!(mox_mod)
        end)
      end
  end

  @spec impl_for(:all | :none | atom() | [atom()]) :: [atom()]
  defp impl_for(impl_for) do
    impl_for =
      case impl_for do
        :all -> @impls
        :none -> []
        transition when is_atom(transition) -> [transition]
        list when is_list(list) -> list
      end

    if impl_for -- @impls != [] do
      raise CompileError,
        description:
          "allowed `impl_for:` values are: `:all`, `:none`, or any combination of `#{inspect(@impls)}`"
    end

    impl_for
  end

  @spec parse_fsm(module(), String.t(), Macro.Env.t()) :: [Transition.t()]
  defp parse_fsm(syntax, dsl, env) do
    case syntax.parse(dsl, env) do
      {:ok, result} ->
        result

      {:error, description, snippet, _context, {file, line, column}, _offset} ->
        raise SyntaxError,
          file: file,
          line: line,
          column: column,
          description: description,
          snippet: snippet

      {:error, error} ->
        raise TokenMissingError,
          file: env.file,
          line: env.line,
          column: 0,
          opening_delimiter: ~s|"""|,
          description: "description is incomplete, error: #{inspect(error)}",
          snippet: dsl |> String.split("\n", parts: 2) |> hd()
    end
  end

  @spec hard([Transition.t()], boolean() | atom() | [atom()]) :: keyword(Transition.t())
  defp hard(fsm, auto_terminate) do
    hard =
      fsm
      |> Transition.determined()
      |> Enum.filter(fn
        {state, :__end__} ->
          case auto_terminate do
            ^state -> true
            true -> true
            list when is_list(list) -> state in list
            _ -> false
          end

        {_state, event} ->
          event
          |> to_string()
          |> String.ends_with?("!")
      end)

    [Transition.hard(fsm), hard]
    |> Enum.map(fn h -> h |> Enum.map(&elem(&1, 1)) |> Enum.uniq() end)
    |> Enum.reduce(&Kernel.--/2)
    |> unless do
      raise CompileError,
        description:
          "transitions marked as `:hard` must be determined, non-determined found: #{inspect(Transition.hard(fsm) -- hard)}"
    end

    Enum.map(hard, fn {from, event} ->
      tos =
        fsm
        |> Enum.filter(&match?(%Transition{from: ^from, event: ^event}, &1))
        |> Enum.map(& &1.to)

      {from, %Transition{from: from, event: event, to: tos}}
    end)
  end

  @spec soft([Transition.t()]) :: [Transition.t()]
  defp soft(fsm) do
    Enum.filter(fsm, fn %Transition{event: event} ->
      event
      |> to_string()
      |> String.ends_with?("?")
    end)
  end

  @spec ensure_entry(boolean() | [atom()], [Transition.t()]) :: [atom()]
  defp ensure_entry(ensure_entry, fsm) do
    case ensure_entry do
      list when is_list(list) -> list
      true -> [Transition.entry(fsm)]
      _ -> []
    end
  end
end
