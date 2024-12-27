defmodule Finitomata.Flow.Test do
  use ExUnit.Case, async: true

  alias Finitomata.Test.Flow, as: Flow
  alias Finitomata.Test.Flow.SubFlow1, as: SubFlow

  import ExUnit.CaptureLog

  doctest Finitomata.Flow

  setup_all do
    {:ok, pid} = start_supervised({Finitomata.Supervisor, id: Fini})
    [finitomata: pid]
  end

  test "Invokes a subflow and runs it till the end" do
    Finitomata.start_fsm(Fini, Flow, "Flow", %{fork_data: %{id: :id, object: %{flow: :flow}}})
    assert %{"Flow" => %{module: Finitomata.Test.Flow, pid: pid}} = all = Finitomata.all(Fini)
    assert map_size(all) >= 1
    assert is_pid(pid)

    assert :ok = Finitomata.transition(Fini, "Flow", :to_s2)
    assert %{current: :s2, history: [:s1, :*], payload: %{}} = Finitomata.state(Fini, "Flow")
    assert %{{:fork, :s2, "Flow"} => %{module: SubFlow, pid: pid}} = all = Finitomata.all(Fini)
    assert map_size(all) >= 2
    assert is_pid(pid)

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "Flow"})

    {result, log} =
      with_log(fn ->
        Finitomata.Flow.event({Fini, {:fork, :s2, "Flow"}}, :submit_otp, :confirm_photo, %{
          foo: 42
        })
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, {:ok, {%{foo: 42}, :id, %{flow: :flow}}}} == result
    assert log =~ "[warning]   handler transfer_verify_otp/3"

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata__flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [
                   {:new, :submit_otp, {:ok, {%{foo: 42}, :id, %{flow: :flow}}}},
                   {:*, :__start__, :ok}
                 ]
               },
               steps: %{left: 1, passed: 1}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "Flow"})

    {result, log} =
      with_log(fn ->
        Finitomata.Flow.event({Fini, {:fork, :s2, "Flow"}}, :confirm_photo)
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {
             :error,
             %{
               id: :id,
               owner: %{id: Fini, name: "Flow", pid: _, event: :to_s3},
               history: %{
                 current: 0,
                 steps: [
                   {:new, :submit_otp, {:ok, {%{foo: 42}, :id, %{flow: :flow}}}},
                   {:*, :__start__, :ok}
                 ]
               },
               steps: %{left: 1, passed: 1},
               object: %{flow: :flow}
             }
           } = result

    refute log =~ "[warning]   handler"

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata__flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [
                   {:new, :submit_otp, {:ok, {%{foo: 42}, :id, %{flow: :flow}}}},
                   {:*, :__start__, :ok}
                 ]
               },
               steps: %{left: 1, passed: 1}
             },
             last_error: %{
               error:
                 {:error,
                  {:ambiguous_transition, {:confirm_photo, :confirm_photo},
                   [:confirm_photo, :enter_name, :new, :take_photo]}}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "Flow"})

    {result, log} =
      with_log(fn ->
        Finitomata.Flow.event({Fini, {:fork, :s2, "Flow"}}, :finalize, %{param1: 42})
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert :fsm_gone = result
    refute log =~ "[warning]   handler finalize/3"

    assert log =~
             "[warning] Implementation for finalize is here with args [params: %{param1: 42}, id: :id, object: %{flow: :flow}]"

    refute Finitomata.state(Fini, {:fork, :s2, "Flow"})
  end

  test "Invokes a subflow and fast-forwards it to a state by shortest path" do
    Finitomata.start_fsm(Fini, Flow, "FlowFFS", %{fork_data: %{id: :id, object: %{flow: :flow}}})
    assert %{"FlowFFS" => %{module: Finitomata.Test.Flow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert :ok = Finitomata.transition(Fini, "FlowFFS", :to_s2)
    assert %{current: :s2, history: [:s1, :*], payload: %{}} = Finitomata.state(Fini, "FlowFFS")
    assert %{{:fork, :s2, "FlowFFS"} => %{module: SubFlow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFS"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward({Fini, {:fork, :s2, "FlowFFS"}}, :new)
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, []} == result

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFS"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward({Fini, {:fork, :s2, "FlowFFS"}}, :confirm_photo)
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, [transfer_number: {:confirm_photo, {:ok, {nil, :id, %{flow: :flow}}}}]} == result

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata__flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [
                   {:new, :transfer_number, {:ok, {nil, :id, %{flow: :flow}}}},
                   {:*, :__start__, :ok}
                 ]
               },
               steps: %{left: 1, passed: 1}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFS"})

    {result, log} =
      with_log(fn ->
        Finitomata.Flow.event({Fini, {:fork, :s2, "FlowFFS"}}, :finalize, %{param1: 42})
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert :fsm_gone = result
    refute log =~ "[warning]   handler finalize/3"

    assert log =~
             "[warning] Implementation for finalize is here with args [params: %{param1: 42}, id: :id, object: %{flow: :flow}]"

    refute Finitomata.state(Fini, {:fork, :s2, "FlowFFS"})
  end

  test "Invokes a subflow and fast-forwards it by a path given" do
    Finitomata.start_fsm(Fini, Flow, "FlowFFP", %{fork_data: %{id: :id, object: %{flow: :flow}}})
    assert %{"FlowFFP" => %{module: Finitomata.Test.Flow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert :ok = Finitomata.transition(Fini, "FlowFFP", :to_s2)
    assert %{current: :s2, history: [:s1, :*], payload: %{}} = Finitomata.state(Fini, "FlowFFP")
    assert %{{:fork, :s2, "FlowFFP"} => %{module: SubFlow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFP"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward({Fini, {:fork, :s2, "FlowFFP"}}, :new)
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, []} == result

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFP"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward({Fini, {:fork, :s2, "FlowFFP"}}, %Finitomata.Transition.Path{
          from: :new,
          to: :confirm_photo,
          path: [start: :confirm_photo]
        })
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, [start: {:confirm_photo, :recipient_flow_name}]} == result

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata__flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [
                   {:new, :start, :recipient_flow_name},
                   {:*, :__start__, :ok}
                 ]
               },
               steps: %{left: 1, passed: 1}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFP"})

    {result, log} =
      with_log(fn ->
        Finitomata.Flow.event({Fini, {:fork, :s2, "FlowFFP"}}, :finalize, %{param1: 42})
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert :fsm_gone = result
    refute log =~ "[warning]   handler finalize/3"

    assert log =~
             "[warning] Implementation for finalize is here with args [params: %{param1: 42}, id: :id, object: %{flow: :flow}]"

    refute Finitomata.state(Fini, {:fork, :s2, "FlowFFP"})
  end

  test "Invokes a subflow and fast-forwards it by a breadcrumbs given" do
    Finitomata.start_fsm(Fini, Flow, "FlowFFB", %{fork_data: %{id: :id, object: %{flow: :flow}}})
    assert %{"FlowFFB" => %{module: Finitomata.Test.Flow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert :ok = Finitomata.transition(Fini, "FlowFFB", :to_s2)
    assert %{current: :s2, history: [:s1, :*], payload: %{}} = Finitomata.state(Fini, "FlowFFB")
    assert %{{:fork, :s2, "FlowFFB"} => %{module: SubFlow, pid: pid}} = Finitomata.all(Fini)
    assert is_pid(pid)

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFB"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward({Fini, {:fork, :s2, "FlowFFB"}}, :new)
        |> tap(fn _ -> Process.sleep(100) end)
      end)

    assert {:ok, []} == result

    assert %{
             current: :new,
             history: [:finitomata__flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "FlowFFB"})

    {result, _log} =
      with_log(fn ->
        Finitomata.Flow.fast_forward(
          {Fini, {:fork, :s2, "FlowFFB"}},
          [
            :confirm_photo,
            :finitomata__flowed
          ],
          skip_handlers?: true
        )
        |> tap(fn _ -> Process.sleep(300) end)
      end)

    assert {:fsm_gone, [transfer_number: {:confirm_photo, :skipped}]} == result

    refute Finitomata.state(Fini, {:fork, :s2, "FlowFFB"})
  end
end
