defmodule Finitomata.Test.Plant do
  @moduledoc false

  @fsm """
  [*] --> s1 : to_s1
  s1 --> s2 : to_s2
  s1 --> s3 : to_s3
  s2 --> [*] : ok
  s3 --> [*] : ok
  """

  use Finitomata, {@fsm, :state_diagram}

  @impl Finitomata
  def on_transition(:s1, :to_s2, event_payload, state_payload) do
    Logger.info(
      "[✓ ⇄] with: " <>
        inspect(
          event_payload: event_payload,
          state: state_payload
        )
    )

    {:ok, :s2, state_payload}
  end
end

defmodule Finitomata.Test.Transition do
  @moduledoc false

  @fsm """
  idle --> |start| started
  started --> |accept| accepted
  started --> |reject| rejected
  accepted --> |accept| accepted
  accepted --> |reject| rejected
  accepted --> |end| done
  rejected --> |restart| started
  rejected --> |end| done
  done --> |end!| ended
  """

  use Finitomata, fsm: @fsm, listener: :mox, hibernate: true, cache_state: false
end

defmodule Finitomata.Test.Hard do
  @moduledoc false

  @fsm """
  idle --> |start| ready
  ready --> |do!| ready
  ready --> |do!| reload
  ready --> |do!| done
  reload --> |reloaded!| ready
  done --> |end!| ended
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: :mox

  @impl Finitomata
  def on_transition(:ready, :do!, _, state) do
    {:ok, :done, state}
  end
end

defmodule Finitomata.Test.Sequenced do
  @moduledoc false

  @fsm """
  idle --> |start| started
  started --> |accept!| accepted
  accepted --> |reject!| rejected
  rejected --> |end| done
  done --> |end!| ended
  """

  defmodule Listener do
    @moduledoc false

    require Logger

    @behaviour Finitomata.Listener
    @impl Finitomata.Listener
    def after_transition(id, state, payload) do
      Logger.warning(inspect(id: id, state: state, payload: payload))
    end
  end

  use Finitomata, fsm: @fsm, listener: {:mox, Listener}
end

defmodule Finitomata.Test.Log do
  @moduledoc false

  @fsm """
  idle --> |accept| accepted
  idle --> |reject| rejected
  """

  use Finitomata, fsm: @fsm, syntax: Finitomata.Mermaid, impl_for: :all
end

defmodule Finitomata.Test.WithMocks do
  @moduledoc false

  defmodule ExtBehaviour do
    @moduledoc false
    @callback void(term()) :: term()
  end

  @fsm """
  idle --> |process| processed
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: :mox

  @behaviour ExtBehaviour

  @impl ExtBehaviour
  def void(term), do: term

  Mox.defmock(Finitomata.Test.WithMocks.ExtBehaviour.Mox,
    for: Finitomata.Test.WithMocks.ExtBehaviour
  )

  @ext_behaviour Application.compile_env(:finitomata, :ext_behaviour, __MODULE__)

  @impl Finitomata
  def on_transition(:idle, :process, _, state_payload) do
    state_payload = @ext_behaviour.void(state_payload)
    {:ok, :processed, state_payload}
  end
end

defmodule Finitomata.Test.Callback do
  @moduledoc false

  @fsm """
  idle --> |process| processed
  """

  use Finitomata, fsm: @fsm

  @impl Finitomata
  def on_transition(:idle, :process, %{pid: pid}, state_payload) do
    send(pid, :on_transition)

    {:ok, :processed, Map.put(state_payload, :pid, pid)}
  end
end

defmodule Finitomata.Test.Timer do
  @moduledoc false

  @fsm """
  idle --> |process| processing
  processing --> |finish| finished
  """

  use Finitomata, fsm: @fsm, syntax: :flowchart, timer: 100

  @impl Finitomata
  def on_timer(:idle, state) do
    send(state.payload.pid, :on_transition)
    {:transition, :process, state.payload}
  end

  def on_timer(:processing, state) do
    send(state.payload.pid, :on_timer)
    {:ok, Map.put(state.payload, :processing, true)}
  end
end

defmodule Finitomata.Test.TimerExUnit do
  @moduledoc false

  @fsm """
  idle --> |process| processing
  processing --> |finish| finished
  """

  use Finitomata, fsm: @fsm, timer: 1_000, listener: :mox

  @impl Finitomata
  def on_timer(:idle, state) do
    send(state.payload.pid, :on_transition)
    {:transition, :process, state.payload}
  end

  def on_timer(:processing, state) do
    send(state.payload.pid, :on_timer)
    {:ok, Map.put(state.payload, :processing, true)}
  end
end

defmodule Finitomata.Test.Auto do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |do!| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  @impl Finitomata
  def on_transition(:idle, :start!, _, state) do
    send(state.pid, :on_start!)
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do!, _, state) do
    send(state.pid, :on_do!)
    {:ok, :done, state}
  end

  @impl Finitomata
  def on_transition(:done, :__end__, _, state) do
    send(state.pid, :on_end)
    {:ok, :*, state}
  end
end

defmodule Finitomata.Test.AutoExUnit do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |do!| done
  done --> |exit| exited
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: :mox

  @impl Finitomata
  def on_transition(:idle, :start!, _, state) do
    {:ok, :started, state}
  end

  @impl Finitomata
  def on_transition(:started, :do!, _, state) do
    {:ok, :done, state}
  end

  @impl Finitomata
  def on_transition(:exited, :__end__, _, state) do
    {:ok, :*, state}
  end
end

defmodule Finitomata.Test.EnsureEntry do
  @moduledoc false

  @fsm """
  idle --> |process!| processed
  """

  use Finitomata, fsm: @fsm, ensure_entry: true, auto_terminate: true

  @impl Finitomata
  def on_transition(:*, :__start__, %{__retries__: 3} = payload, %{pid: pid} = state) do
    Logger.debug("[:*] Exhausted: " <> inspect({payload, state}))
    send(pid, :exhausted)
    {:ok, :idle, state}
  end

  @impl Finitomata
  def on_transition(:*, :__start__, %{__retries__: retries} = payload, %{pid: pid} = state) do
    Logger.debug("[:*] State: " <> inspect({payload, state}))
    send(pid, :"retrying_#{retries}")
    {:error, :not_yet}
  end

  @impl Finitomata
  def on_transition(:idle, :process!, payload, %{pid: pid} = state) do
    Logger.debug("[:idle] State: " <> inspect({payload, state}))
    send(pid, :on_process!)
    {:ok, :processed, state}
  end
end

defmodule Finitomata.Test.Soft do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |do?| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  @impl Finitomata
  def on_transition(:started, :do?, _payload, _state) do
    {:error, :not_allowed}
  end
end

defmodule Finitomata.Test.ErrorAttach do
  @moduledoc false

  @fsm """
  idle --> |start| started
  """

  use Finitomata, fsm: @fsm, auto_terminate: true

  @impl Finitomata
  def on_transition(:idle, :start, _payload, _state) do
    raise "Test error"
  end

  @impl Finitomata
  def on_failure(_event, _payload, %{last_error: last_error} = _state) do
    Logger.debug("[failure] " <> inspect(last_error.error))
    Logger.debug("[failure] state: " <> inspect(last_error.state))
    Logger.debug("[failure] event: " <> inspect(last_error.event))
  end
end

defmodule Finitomata.Test.Determined do
  @moduledoc false

  @fsm """
  idle --> |start!| started
  started --> |step!| step1
  step1 --> |step!| step2
  step2 --> |continue| step3
  step3 --> |exit!| done
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, listener: :mox

  @impl Finitomata
  def on_transition(:started, :step!, _, state) do
    {:ok, :step1, Map.update(state, :step, 1, &(&1 + 1))}
  end

  def on_transition(:step1, :step!, _, state) do
    {:ok, :step2, Map.update(state, :step, 1, &(&1 + 1))}
  end

  def on_transition(:step2, :continue, data, state) do
    {:ok, :step3, Map.put(state, :data, data)}
  end
end
