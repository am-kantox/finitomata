defmodule Finitomata.Flow.Test do
  use ExUnit.Case, async: true

  alias Finitomata.Test.Flow, as: Flow
  alias Finitomata.Test.Flow.SubFlow1, as: SubFlow

  doctest Finitomata.Flow

  setup_all do
    {:ok, pid} = start_supervised({Finitomata.Supervisor, id: Fini})
    [finitomata: pid]
  end

  test "Invokes a subflow and runs it till the end" do
    Finitomata.start_fsm(Fini, Flow, "Flow", %{})
    assert %{"Flow" => %{module: Finitomata.Test.Flow, pid: pid}} = all = Finitomata.all(Fini)
    assert map_size(all) == 1
    assert is_pid(pid)

    assert :ok = Finitomata.transition(Fini, "Flow", :to_s2)
    assert %{current: :s2, history: [:s1, :*], payload: %{}} = Finitomata.state(Fini, "Flow")
    assert %{{:fork, :s2, "Flow"} => %{module: SubFlow, pid: pid}} = all = Finitomata.all(Fini)
    assert map_size(all) == 2
    assert is_pid(pid)

    assert %{
             current: :new,
             history: [:finitomata_flowing, :*],
             payload: %{
               history: %{current: 0, steps: [{:*, :__start__, :ok}]},
               steps: %{left: 2, passed: 0}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "Flow"})

    assert {:ok, nil} =
             SubFlow.event({Fini, {:fork, :s2, "Flow"}}, :submit_otp, :confirm_photo, %{foo: 42})

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata_flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [{:new, :submit_otp, nil}, {:*, :__start__, :ok}]
               },
               steps: %{left: 1, passed: 1}
             }
           } = Finitomata.state(Fini, {:fork, :s2, "Flow"})

    assert {
             :error,
             %{
               id: nil,
               owner: %{id: Fini, name: "Flow", pid: _, event: :to_s3},
               history: %{current: 0, steps: [{:new, :submit_otp, nil}, {:*, :__start__, :ok}]},
               steps: %{left: 1, passed: 1},
               object: nil
             }
           } = SubFlow.event({Fini, {:fork, :s2, "Flow"}}, :confirm_photo)

    assert %{
             current: :confirm_photo,
             history: [:new, :finitomata_flowing, :*],
             payload: %{
               history: %{
                 current: 0,
                 steps: [{:new, :submit_otp, nil}, {:*, :__start__, :ok}]
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

    assert :fsm_gone = SubFlow.event({Fini, {:fork, :s2, "Flow"}}, :finalize)
    refute Finitomata.state(Fini, {:fork, :s2, "Flow"})
  end
end
