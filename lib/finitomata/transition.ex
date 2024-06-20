defmodule Finitomata.Transition do
  @moduledoc """
  The internal representation of `Transition`.

  It includes `from` and `to` states, and the `event`, all represented as atoms.
  """

  alias Finitomata.Transition

  @typedoc "The state of FSM"
  @type state :: atom()
  @typedoc "The event in FSM"
  @type event :: atom()
  @typedoc "The kind of event"
  @type event_kind :: :soft | :hard | :normal

  @typedoc """
  The transition is represented by `from` and `to` states _and_ the `event`.
  """
  @type t :: %{
          __struct__: Transition,
          from: state(),
          to: state() | [state()],
          event: event()
        }
  @enforce_keys [:from, :to, :event]
  defstruct [:from, :to, :event]

  defmodule Path do
    @moduledoc "The path from one state to another one"

    alias Finitomata.Transition

    @type t :: %{
            __struct__: Path,
            from: Transition.state(),
            to: Transition.state(),
            path: [{Transition.event(), Transition.state()}]
          }

    @enforce_keys [:from, :to, :path]
    defstruct [:from, :to, :path]

    defimpl Inspect do
      @moduledoc false

      import Inspect.Algebra

      def inspect(%Finitomata.Transition.Path{from: from, to: to, path: path}, opts) do
        fancy =
          case Keyword.get(opts.custom_options, :fancy, true) do
            false -> false
            {from, to} -> %{from: from, to: to}
            %{} = map -> Map.merge(%{from: " ⇥ ", to: " ↦ "}, map)
            _ -> %{from: " ⇥ ", to: " ↦ "}
          end

        fancy_path =
          if is_map(fancy) do
            path
            |> Enum.reduce([], fn {event, to}, acc ->
              [to_doc(to, opts), fancy.to, to_doc("#{event}", opts), fancy.from | acc]
            end)
            |> Enum.reverse()
          end

        case {from == to and from != :*, is_map(fancy)} do
          {true, false} ->
            inner = [around: from, path: path]
            concat(["#Finitomata.Loop<", to_doc(inner, opts), ">"])

          {false, false} ->
            inner = [from: from, to: to, path: path]
            concat(["#Finitomata.Path<", to_doc(inner, opts), ">"])

          {true, _} ->
            concat(["↺‹", to_doc(from, opts) | fancy_path] ++ ["›"])

          {false, _} ->
            concat(["↝‹", to_doc(from, opts) | fancy_path] ++ ["›"])
        end
      end
    end
  end

  @doc false
  @spec from_parsed([binary()]) :: t()
  def from_parsed([from, to, event])
      when is_binary(from) and is_binary(to) and is_binary(event) do
    [from, to, event] =
      Enum.map(
        [from, to, event],
        &(&1 |> String.trim_leading("[") |> String.trim_trailing("]") |> String.to_atom())
      )

    %Transition{from: from, to: to, event: event}
  end

  @doc ~S"""
  Returns the kind of event.

  If event ends up with an exclamation sign, it’s `:hard`, meaning the respective
    transition would be initiated automatically when the `from` state of such a transition
    is reached.

  If event ends up with a question mark, it’s `:soft`, meaning no error would have
    been reported in a case transition fails.

  Otherwise the event is `:normal`.

      iex> {:ok, [_, hard, _]} =
      ...>   Finitomata.PlantUML.parse("[*] --> entry : foo\nentry --> exit : go!\nexit --> [*] : terminate")
      ...> Finitomata.Transition.event_kind(hard)
      :hard
  """
  @spec event_kind(event() | t()) :: event_kind()
  def event_kind(%Transition{event: event}), do: event_kind(event)

  def event_kind(event) do
    event = to_string(event)

    cond do
      String.ends_with?(event, "!") -> :hard
      String.ends_with?(event, "?") -> :soft
      true -> :normal
    end
  end

  @doc ~S"""
  Returns the state _after_ starting one, so-called `entry` state.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> entry : foo\nentry --> exit : go\nexit --> [*] : terminate")
      ...> Finitomata.Transition.entry(transitions)
      :entry
  """
  @spec entry(:state | :transition, [t()]) :: state()
  def entry(what \\ :state, transitions)

  def entry(:transition, transitions),
    do: Enum.find(transitions, &match?(%Transition{from: :*}, &1))

  def entry(:state, transitions), do: entry(:transition, transitions).to

  @doc ~S"""
  Returns the states _before_ ending one, so-called `exit` states.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "entry --> |process| processing\nprocessing --> |ok| success\nprocessing --> |ko| error"
      ...>   )
      ...> Finitomata.Transition.exit(transitions)
      [:error, :success]
  """
  @spec exit(:states | :transitions, [t()]) :: [state()]
  def exit(what \\ :states, transitions)

  def exit(:transitions, transitions) do
    Enum.reduce(transitions, [], fn
      %Transition{to: :*} = t, acc -> [t | acc]
      _, acc -> acc
    end)
  end

  def exit(:states, transitions),
    do: :transitions |> Transition.exit(transitions) |> Enum.map(& &1.from)

  @doc ~S"""
  Returns all the hard transitions which inevitably lead to the next state
    (events ending with an exclamation sign,)
    which makes the _FSM_ to go to the next state with `:continue` callback.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> entry : start\nentry --> exit : go!\nexit --> [*] : terminate")
      ...> Finitomata.Transition.hard(transitions)
      [entry: :go!]
      ...> Finitomata.Transition.hard(:transitions, transitions)
      [%Finitomata.Transition{from: :entry, to: :exit, event: :go!}]
  """
  @spec hard(:states | :transitions, [t()]) :: Enumerable.t(t()) | [Path.t()]
  def hard(states \\ :states, transitions)

  def hard(:states, transitions) do
    :transitions
    |> hard(transitions)
    |> Enum.map(&{&1.from, &1.event})
  end

  def hard(:transitions, transitions) do
    Enum.filter(transitions, &(event_kind(&1) == :hard))
  end

  @doc ~S"""
  Returns the continuation from the state given which inevitably lead to other state(s).

  All the transitions from this state are hard (ending with `!`,)
    which makes the _FSM_ to go through all these states in `:continue` callbacks.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> entry : start\nentry --> exit : go!\nexit --> done : finish\ndone --> [*] : terminate")
      ...> Finitomata.Transition.continuation(:entry, Finitomata.Transition.hard(:transitions, transitions))
      [%Finitomata.Transition.Path{from: :entry, to: :exit, path: [go!: :exit]}]
  """
  @spec continuation(:states | :transitions, state(), [t()]) :: nil | [Path.t()] | [t()]
  def continuation(states \\ :states, from, transitions)

  def continuation(:states, from, transitions) do
    :transitions
    |> continuation(from, transitions)
    |> case do
      [] -> nil
      path -> to_path([path])
    end
  end

  def continuation(:transitions, from, transitions) do
    do_continuation(from, transitions, [])
  end

  defp do_continuation(from, transitions, path) do
    transitions
    |> Enum.flat_map(fn
      %Transition{from: from_to, to: from_to} ->
        Enum.reverse(path)

      %Transition{from: ^from, to: to} = t ->
        if Enum.member?(path, t), do: [], else: do_continuation(to, transitions, [t | path])

      _other ->
        Enum.reverse(path)
    end)
    |> Enum.uniq()
  end

  @doc ~S"""
  Returns all the states which inevitably lead to the ending one.

  All the transitions from these states to the ending one are hard (ending with `!`,)
    which makes the _FSM_ to go through all these states in `:continue` callbacks.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> entry : start\nentry --> exit : go!\nexit --> [*] : terminate")
      ...> Finitomata.Transition.exiting(transitions)
      [%Finitomata.Transition.Path{from: :entry, to: :*, path: [go!: :exit, terminate: :*]}]
  """
  @spec exiting(:states | :transitions, [t()]) :: Enumerable.t([t()]) | [Path.t()]
  def exiting(what \\ :states, transitions)

  def exiting(:states, transitions) do
    :transitions
    |> exiting(transitions)
    |> to_path()
  end

  def exiting(:transitions, transitions) do
    :transitions
    |> paths(transitions)
    |> Stream.filter(fn path ->
      path
      |> Enum.reverse()
      |> then(&match?([%Transition{to: :*} | _], &1))
    end)
    |> Stream.map(fn path ->
      [last | rest] = Enum.reverse(path)
      rest = Enum.take_while(rest, &(event_kind(&1) == :hard))
      Enum.reverse([last | rest])
    end)
    |> Stream.uniq()
  end

  @doc false
  def flatten(%Transition{to: to} = transition) when is_atom(to),
    do: [transition]

  def flatten(%Transition{from: from, to: to, event: event}) when is_list(to),
    do: Enum.map(to, &%Transition{from: from, to: &1, event: event})

  @doc ~S"""
  Returns all the loops aka internal paths where starting and ending states are the same one.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> s1 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.loops(transitions)
      [%Finitomata.Transition.Path{from: :s1, to: :s1, path: [ok: :s2, ok: :s1]},
       %Finitomata.Transition.Path{from: :s2, to: :s2, path: [ok: :s1, ok: :s2]}]
  """
  @spec loops(:states | :transitions, [t()]) :: Enumerable.t(t()) | [Path.t()]
  def loops(what \\ :states, transitions)

  def loops(:transitions, transitions) do
    transitions
    |> states(true)
    |> Stream.flat_map(&do_loop(&1, transitions, [], []))
  end

  def loops(:states, transitions) do
    :transitions
    |> loops(transitions)
    |> to_path()
  end

  defp do_loop(state, _transitions, [%Transition{from: state} | _] = path, paths),
    do: [path | paths]

  defp do_loop(state, transitions, path, paths) do
    transitions
    |> Stream.reject(&(&1 in path))
    |> Stream.filter(&match?(%Transition{from: ^state, to: to} when to != :*, &1))
    |> Stream.flat_map(&do_loop(&1.to, transitions, path ++ [&1], paths))
  end

  @doc ~S"""
  Returns all the paths from starting to ending state.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns1 --> s3 : ok\ns2 --> [*] : ko\ns3 --> [*] : ko")
      ...> Finitomata.Transition.paths(transitions)
      [%Finitomata.Transition.Path{from: :*, to: :*, path: [foo: :s1, ok: :s2, ko: :*]},
       %Finitomata.Transition.Path{from: :*, to: :*, path: [foo: :s1, ok: :s3, ko: :*]}]
  """
  @spec paths(:states | :transitions, [t()], state(), state()) :: Enumerable.t(t()) | [Path.t()]
  def paths(what \\ :states, transitions, from \\ :*, to \\ :*)

  def paths(:states, transitions, from, to) do
    :transitions
    |> paths(transitions, from, to)
    |> to_path()
  end

  def paths(:transitions, transitions, :*, to) do
    entry = entry(:transition, transitions)
    do_path(entry.to, to, transitions, [entry], [])
  end

  def paths(:transitions, transitions, from, to) do
    do_path(from, to, transitions, [], [])
  end

  defp do_path(to, to, _transitions, [_ | _] = path, paths), do: [Enum.reverse(path) | paths]
  defp do_path(to, to, _transitions, [], paths), do: paths
  defp do_path(:*, _, _transitions, _, paths), do: paths

  defp do_path(from, to, transitions, path, paths) do
    transitions
    |> Stream.reject(&(&1 in path))
    |> Stream.filter(&match?(%Transition{from: ^from}, &1))
    |> Stream.flat_map(&do_path(&1.to, to, transitions, [&1 | path], paths))
  end

  @doc ~S"""
  Returns `true` if the transition `from` → `to` is allowed, `false` otherwise.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed?(transitions, :s1, :s2)
      true
      ...> Finitomata.Transition.allowed?(transitions, :s1, :*)
      false
  """
  @spec allowed?([t()], state(), state()) :: boolean()
  def allowed?(transitions, from, to) do
    Enum.any?(transitions, &match?(%Transition{from: ^from, to: ^to}, &1))
  end

  @doc ~S"""
  Returns `true` if the state `from` hsa an outgoing transition with `event`, false otherwise.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.responds?(transitions, :s1, :ok)
      true
      ...> Finitomata.Transition.responds?(transitions, :s1, :ko)
      false
  """
  @spec responds?([t()], state(), event()) :: boolean()
  def responds?(transitions, from, event) do
    Enum.any?(transitions, &match?(%Transition{from: ^from, event: ^event}, &1))
  end

  @doc ~S"""
  Returns the list of all the transitions, matching the options.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s3| s3")
      ...> Finitomata.Transition.allowed(transitions, to: [:idle, :*])
      [{:*, :idle, :__start__}, {:s3, :*, :__end__}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1)
      [{:s1, :s2, :to_s2}, {:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1, to: :s3)
      [{:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s1, with: :to_s3)
      [{:s1, :s3, :to_s3}]
      iex> Finitomata.Transition.allowed(transitions, from: :s2, with: :to_s2)
      []
  """
  @spec allowed([t()], [
          {:from, state()} | {:to, state()} | {:with, event()} | {:as, :states | :transitions}
        ]) :: [
          {state(), state(), event()}
        ]
  def allowed(transitions, options \\ []) do
    {as, options} = Keyword.pop(options, :as, :states)

    from = List.wrap(options[:from])
    to = List.wrap(options[:to])
    event = List.wrap(options[:with])

    do_allowed(as, {from, to, event}, transitions)
  end

  defp do_allowed(:states, fte, transitions) do
    :transitions
    |> do_allowed(fte, transitions)
    |> Enum.map(&{&1.from, &1.to, &1.event})
  end

  defp do_allowed(:transitions, fte, transitions) do
    case fte do
      {[], [], []} ->
        transitions

      {fa, [], []} ->
        for %Transition{from: from} = t <- transitions, from in fa, do: t

      {[], ta, []} ->
        for %Transition{to: to} = t <- transitions, to in ta, do: t

      {[], [], ea} ->
        for %Transition{event: event} = t <- transitions, event in ea, do: t

      {fa, ta, []} ->
        for %Transition{from: from, to: to} = t <- transitions, from in fa and to in ta, do: t

      {fa, [], ea} ->
        for %Transition{from: from, event: event} = t <- transitions,
            from in fa and event in ea,
            do: t

      {[], ta, ea} ->
        for %Transition{to: to, event: event} = t <- transitions, to in ta and event in ea, do: t

      {fa, ta, ea} ->
        for %Transition{from: from, to: to, event: event} = t <- transitions,
            from in fa and to in ta and event in ea,
            do: t
    end
  end

  @doc ~S"""
  Returns the list of all the transitions, matching the `from` state and the `event`.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.allowed(transitions, :s1, :foo)
      [:s2]
      ...> Finitomata.Transition.allowed(transitions, :s1, :*)
      []
  """
  @spec allowed([t()], state(), event()) :: [state()]
  def allowed(transitions, from, event) do
    for %Transition{from: ^from, to: to, event: ^event} <- transitions, do: to
  end

  @doc ~S"""
  Returns keyword list of
    `{Finitomata.Transition.state(), Finitomata.Transition.event()}` tuples
    for determined transition from the current state.

  The transition is determined, if it is the only transition allowed from the state.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s1| s3\n" <>
      ...>     "s2 --> |ambiguous| s3\n" <>
      ...>     "s2 --> |ambiguous| s4\n" <>
      ...>     "s3 --> |determined| s3\n" <>
      ...>     "s3 --> |determined| s4\n")
      ...> Finitomata.Transition.determined(transitions)
      [s4: :__end__, s3: :determined, idle: :to_s1]
  """
  @spec determined([t()]) :: [{state(), {event(), state()}}]
  def determined(transitions) do
    transitions
    |> states(true)
    |> Enum.reduce([], fn state, acc ->
      transitions
      |> allowed(from: state)
      |> Enum.group_by(fn {state, _, event} -> {state, event} end)
      |> Map.to_list()
      |> case do
        [{{^state, event}, [_ | _]}] -> [{state, event} | acc]
        _ -> acc
      end
    end)
  end

  @doc ~S"""
  Returns `{:ok, {event(), state()}}` tuple if there is a determined transition
    from the current state, `:error` otherwise.

  The transition is determined, if it is the only transition allowed from the state.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s3| s3")
      ...> Finitomata.Transition.determined(transitions, :s1)
      :error
      iex> Finitomata.Transition.determined(transitions, :s2)
      {:ok, {:to_s3, :s3}}
      iex> Finitomata.Transition.determined(transitions, :s3)
      {:ok, {:__end__, :*}}
  """
  @spec determined([t()], state()) :: {:ok, {event(), state()}} | :error
  def determined(transitions, state) do
    transitions
    |> allowed(from: state)
    |> case do
      [{^state, target, event}] -> {:ok, {event, target}}
      _ -> :error
    end
  end

  @doc ~S"""
  Returns keyword list of
    `{Finitomata.Transition.state(), [Finitomata.Transition.event()]}` for transitions
    which do not have a determined _to_ state.

  Used internally for the validations.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse(
      ...>     "idle --> |to_s1| s1\n" <>
      ...>     "s1 --> |to_s2| s2\n" <>
      ...>     "s1 --> |to_s3| s3\n" <>
      ...>     "s2 --> |to_s1| s3\n" <>
      ...>     "s2 --> |ambiguous| s3\n" <>
      ...>     "s2 --> |ambiguous| s4\n" <>
      ...>     "s3 --> |determined| s3\n" <>
      ...>     "s3 --> |determined| s4\n")
      ...> Finitomata.Transition.ambiguous(transitions)
      [s3: {:determined, [:s3, :s4]}, s2: {:ambiguous, [:s3, :s4]}]
  """
  @spec ambiguous([t()]) :: [{state(), {event(), state()}}]
  def ambiguous(transitions) do
    transitions
    |> states()
    |> Enum.reduce([], fn state, acc ->
      transitions
      |> allowed(from: state)
      |> Enum.group_by(fn {state, _, event} -> {state, event} end)
      |> Enum.filter(&match?({_, [_, _ | _]}, &1))
      |> case do
        [{{^state, event}, ambiguous}] ->
          [{state, {event, Enum.map(ambiguous, &elem(&1, 1))}} | acc]

        _ ->
          acc
      end
    end)
  end

  @doc ~S"""
  Returns the not ordered list of states, including or excluding
    the starting and ending states `:*` according to the second argument.

      iex> {:ok, transitions} =
      ...>   Finitomata.PlantUML.parse("[*] --> s1 : foo\ns1 --> s2 : ok\ns2 --> [*] : ko")
      ...> Finitomata.Transition.states(transitions, true)
      [:s1, :s2]
      ...> Finitomata.Transition.states(transitions)
      [:*, :s1, :s2]
  """
  @spec states([t()], boolean()) :: [state()]
  def states(transitions, purge_internal \\ false)

  def states(transitions, false) do
    transitions
    |> Enum.flat_map(fn %Transition{from: from, to: to} -> [from, to] end)
    |> Enum.uniq()
  end

  def states(transitions, true), do: transitions |> states(false) |> Enum.reject(&(&1 == :*))

  @doc ~S"""
  Returns the not ordered list of events, including or excluding
    the internal starting and ending transitions `:__start__` and `__end__`
    according to the second argument.

      iex> {:ok, transitions} =
      ...>   Finitomata.Mermaid.parse("s1 --> |ok| s2\ns1 --> |ko| s3")
      ...> Finitomata.Transition.events(transitions, true)
      [:ok, :ko]
      ...> Finitomata.Transition.events(transitions)
      [:__start__, :ok, :ko, :__end__]
  """
  @spec events([t()], boolean()) :: [state()]
  def events(transitions, purge_internal \\ false)

  def events(transitions, false) do
    transitions
    |> Enum.map(fn %Transition{event: event} -> event end)
    |> Enum.uniq()
  end

  def events(transitions, true),
    do: transitions |> events(false) |> Enum.reject(&(&1 in ~w|__start__ __end__|a))

  @spec to_path(Enumerable.t([t()])) :: [Path.t()]
  defp to_path(transitions) do
    Enum.map(transitions, fn [%Transition{from: from} | _] = transitions ->
      transitions
      |> Enum.reduce([], fn
        %Transition{event: event, to: to}, [] ->
          [{event, to}]

        %Transition{event: event, to: to, from: from}, [{_, from} | _] = acc ->
          [{event, to} | acc]
      end)
      |> then(fn [{_, to} | _] = path -> %Path{from: from, to: to, path: Enum.reverse(path)} end)
    end)
  end

  defimpl Inspect do
    @moduledoc false

    import Inspect.Algebra

    def inspect(%Finitomata.Transition{from: from, to: to, event: event}, opts) do
      case Keyword.get(opts.custom_options, :fancy, true) do
        false ->
          inner = [from: from, to: to, event: event]
          concat(["#Finitomata.Transition<", to_doc(inner, opts), ">"])

        _ ->
          # ‹#{from} -- <#{event}> --> #{inspect(tos)}›
          concat([
            "↹‹",
            to_doc(from, opts),
            " ⇥ ‹#{event}› ↦ ",
            to_doc(to, opts),
            "›"
          ])
      end
    end
  end
end
