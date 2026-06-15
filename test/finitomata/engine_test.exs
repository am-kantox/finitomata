defmodule Finitomata.EngineTest do
  use ExUnit.Case, async: true

  doctest Finitomata.Engine

  describe "event_payload/1" do
    test "wraps a bare event into a retries-carrying map" do
      assert {:go, %{__retries__: 1}} = Finitomata.Engine.event_payload(:go)
    end

    test "increments __retries__ on each pass" do
      assert {:go, %{__retries__: 3}} =
               Finitomata.Engine.event_payload({:go, %{__retries__: 2}})
    end

    test "wraps a non-map payload under :payload" do
      assert {:go, %{payload: 42, __retries__: 1}} =
               Finitomata.Engine.event_payload({:go, 42})
    end
  end

  describe "history/2" do
    test "collapses consecutive re-entries into a counter" do
      assert [{:a, 2}] = Finitomata.Engine.history(:a, [:a])
      assert [{:a, 3}] = Finitomata.Engine.history(:a, [{:a, 2}])
    end

    test "prepends a distinct state" do
      assert [:a, :b | _] = Finitomata.Engine.history(:a, [:b])
    end

    test "caps the history at Finitomata.State.history_size/0" do
      size = Finitomata.State.history_size()
      long = for i <- 1..(size + 5), do: :"s#{i}"
      result = Finitomata.Engine.history(:head, long)
      assert [_ | _] = result
      assert Enum.count(result) == size
      assert hd(result) == :head
    end
  end

  describe "hibernate_noreply/1" do
    test "never hibernates when `hibernate: false`" do
      assert {:noreply, %Finitomata.State{}} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{
                 hibernate: false,
                 current: :a
               })
    end

    test "always hibernates when `hibernate: true`" do
      assert {:noreply, %Finitomata.State{}, :hibernate} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{
                 hibernate: true,
                 current: :a
               })
    end

    test "hibernates only on the listed states when `hibernate: [state()]`" do
      assert {:noreply, %Finitomata.State{}, :hibernate} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{
                 hibernate: [:a, :b],
                 current: :a
               })

      assert {:noreply, %Finitomata.State{}} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{
                 hibernate: [:a, :b],
                 current: :c
               })
    end

    test "hibernates only on the matching state when `hibernate: state()`" do
      assert {:noreply, %Finitomata.State{}, :hibernate} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{hibernate: :a, current: :a})

      assert {:noreply, %Finitomata.State{}} =
               Finitomata.Engine.hibernate_noreply(%Finitomata.State{hibernate: :a, current: :b})
    end
  end

  describe "hibernate_reply/2" do
    test "carries the reply and respects per-state `hibernate:`" do
      assert {:reply, :pong, %Finitomata.State{}, :hibernate} =
               Finitomata.Engine.hibernate_reply(:pong, %Finitomata.State{
                 hibernate: [:a],
                 current: :a
               })

      assert {:reply, :pong, %Finitomata.State{}} =
               Finitomata.Engine.hibernate_reply(:pong, %Finitomata.State{
                 hibernate: [:a],
                 current: :b
               })
    end
  end
end
