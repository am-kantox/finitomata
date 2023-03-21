defmodule ExUnitFinitomata do
  @moduledoc """
  Helpers and assertions to make `Finitomata` implementation easily testable.
  """

  @states Finitomata.Test.Listener.states()

  @doc false
  def estructura_path({{:., _, [{hd, _, _}, tl]}, _, []}) do
    [tl | estructura_path(hd)]
  end

  def estructura_path({leaf, _, args}) when args in [nil, []], do: estructura_path(leaf)
  def estructura_path(leaf), do: [leaf]

  defmacro init_finitomata(id \\ nil, impl, name, payload, options \\ []) do
    quote generated: true,
          location: :keep,
          bind_quoted: [id: id, impl: impl, name: name, payload: payload, options: options] do
      mock = Module.concat(impl, "Mox")
      fsm_name = {:via, Registry, {Finitomata.Supervisor.fq_module(id, Registry, true), name}}
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
  end

  defmacro assert_transition(id \\ nil, name, event_payload, to_state, do: block) do
    block =
      block
      |> Enum.map(fn {:->, _meta, [[{_, _, _} = var], match_ast]} ->
        path = var |> estructura_path() |> Enum.reverse()

        quote do
          assert unquote(match_ast) = get_in(to_state.payload, unquote(path))
        end
      end)

    quote generated: true, location: :keep do
      Finitomata.transition(unquote(id), unquote(name), unquote(event_payload))

      to_state = Finitomata.state(unquote(id), unquote(name), :full)

      case unquote(to_state) do
        nil ->
          assert is_nil(to_state)

        state when state in unquote(@states) ->
          fsm_name =
            {:via, Registry,
             {Finitomata.Supervisor.fq_module(unquote(id), Registry, true), unquote(name)}}

          entry_state = unquote(to_state)
          assert_receive {:on_transition, ^fsm_name, ^entry_state, payload}, 1_000

          assert %Finitomata.State{current: unquote(to_state)} = to_state

          unquote(block)
      end
    end
  end
end
