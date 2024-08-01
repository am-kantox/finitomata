defmodule Finitomata.Accessible do
  @moduledoc since: "0.26.0"
  @moduledoc """
  The convenience module, exposing `start_link/1` to embed `Finitomata.Supervisor`
  implementation into a supervision tree in an agnostic way.

  This module implements `Access` in a contrived way, allowing to deal with underlying
  _FSM_ instances in a following way.

  ```elixir
  iex|🌢|1 ▶ Finitomata.Accessible.start_link(type: Finitomata, implementation: L, id: L1)
  {:ok, #PID<0.214.0>}

  iex|🌢|2 ▶ sup = Finitomata.Accessible.lookup(L1)
  %Finitomata.Accessible{
    type: Finitomata,
    id: L1,
    implementation: Finitomata.Test.Log,
    last_event: nil,
    cached_pid: #PID<0.214.0>
  }

  iex|🌢|3 ▶ put_in(sup, ["MyFSM"], :accept)
  07:16:34.736 [debug] [→ ↹] […]
  07:16:34.738 [debug] [✓ ⇄] with: [current: :*, event: :__start__, event_payload: %{payload: nil, __retries__: 1}, state: %{}]
  07:16:34.738 [debug] [← ↹] […]
  07:16:34.738 [debug] [→ ↹] […]
  07:16:34.739 [debug] [✓ ⇄] with: [current: :idle, event: :accept, event_payload: nil, state: %{}]
  07:16:34.739 [debug] [← ↹] […]

  %Finitomata.Accessible{
    type: Finitomata,
    id: L1,
    implementation: Finitomata.Test.Log,
    last_event: {"MyFSM", :accept},
    cached_pid: #PID<0.214.0>
  }

  iex|🌢|4 ▶ get_in(sup, ["MyFSM"])
  #Finitomata<[
    name: {Finitomata.L1.Registry, "MyFSM"},
    state: [current: :accepted, previous: :idle, payload: %{}],
    internals: [errored?: false, persisted?: false, timer: false]
  ]>
  ```
  """

  schema = [
    type: [
      required: true,
      type: {:custom, Finitomata, :behaviour, [Finitomata.Supervisor]},
      doc:
        "The actual `Finitomata.Supervisor` implementation (typically, `Finitomata` or `Infinitomata`)"
    ],
    implementation: [
      required: true,
      type: :atom,
      doc: "The actual implementation of _FSM_ (the module, having `use Finitomata` clause)"
    ],
    id: [
      required: false,
      default: nil,
      type: :any,
      doc:
        "The unique `ID` of this _Finitomata_ “branch,” when `nil` the `implementation` value would be used"
    ]
  ]

  @schema NimbleOptions.new!(schema)

  @doc """
  Supervision tree embedder.

  ## Options to `Finitomata.Accessible.start_link/1`

  #{NimbleOptions.docs(@schema)}
  """
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @schema)
    type = Keyword.fetch!(opts, :type)
    implementation = Keyword.fetch!(opts, :implementation)
    id = Keyword.fetch!(opts, :id)

    on_start = type.start_link(id)

    case on_start do
      {:ok, pid} ->
        :persistent_term.put(
          {__MODULE__, id},
          struct!(__MODULE__, type: type, id: id, implementation: implementation, cached_pid: pid)
        )

      {:error, {:already_started, pid}} ->
        :persistent_term.put(
          {__MODULE__, id},
          struct!(__MODULE__, type: type, id: id, implementation: implementation, cached_pid: pid)
        )

      _ ->
        nil
    end

    on_start
  end

  @doc """
  Looks up the `Finitomata.Accessible` instance for the given `id`
  """
  @spec lookup(Finitomata.id()) :: t()
  def lookup(id), do: :persistent_term.get({__MODULE__, id}, nil)

  @typedoc "The convenience struct representing the `Finitomata.Supervisor` with `Access`"
  @type t :: %{
          __struct__: __MODULE__,
          type: Finitomata.Supervisor.t(),
          id: Finitomata.id(),
          implementation: module(),
          last_event: nil | {Finitomata.fsm_name(), Finitomata.event_payload()},
          cached_pid: nil | pid()
        }

  defstruct [:type, :id, :implementation, :last_event, :cached_pid]

  @behaviour Access

  @doc false
  @impl Access
  def fetch(%{__struct__: __MODULE__, type: type, id: id}, fsm_name) do
    case type.state(id, fsm_name, :full) do
      %Finitomata.State{} = state -> {:ok, state}
      _ -> :error
    end
  end

  @doc false
  @impl Access
  def pop(%{__struct__: __MODULE__} = data, _key),
    do: {nil, data}

  @doc false
  @impl Access
  def get_and_update(%{__struct__: __MODULE__, type: type, id: id} = data, fsm_name, function) do
    if not type.alive?(id, fsm_name) do
      {:ok, _pid} = type.start_fsm(id, fsm_name, data.implementation, %{})
    end

    state = type.state(id, fsm_name, :full)

    case function.(state) do
      :pop ->
        {state, data}

      {_state, event_payload} ->
        :ok = type.transition(id, fsm_name, event_payload)
        {state, %{data | last_event: {fsm_name, event_payload}}}
    end
  end
end
