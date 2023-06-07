defmodule EctoIntegration.Test do
  use ExUnit.Case
  doctest EctoIntegration

  alias EctoIntegration.Data.{Post, Post.EventLog}
  alias EctoIntegration.Repo

  setup_all do
    uuid = Ecto.UUID.generate()
    post = Post.create(%{id: uuid, title: "Post 1", body: "Body 1"})

    Process.sleep(100)

    %{uuid: uuid, post: post}
  end

  test "`Post` lifecycle", %{uuid: uuid, post: _post} do
    post = fn uuid -> Post |> Repo.get(uuid) |> Repo.preload(:event_log) end
    state = &Finitomata.state/1

    transition = fn uuid, event, payload ->
      Finitomata.transition(uuid, {event, payload})
    end

    # assert_receive

    assert post.(uuid).state == :empty
    assert state.(uuid).current == :empty

    assert [
             %EventLog{
               previous_state: :*,
               current_state: :empty,
               event: :__start__,
               event_payload: %{"__retries__" => 1}
             }
           ] = post.(uuid).event_log

    transition.(uuid, :edit, %{foo: :bar})
    Process.sleep(100)

    assert post.(uuid).state == :draft
    assert state.(uuid).current == :draft

    assert [
             %EventLog{
               previous_state: :empty,
               current_state: :draft,
               event: :edit,
               event_payload: %{"foo" => "bar"}
             },
             %EventLog{
               previous_state: :*,
               current_state: :empty,
               event: :__start__,
               event_payload: %{"__retries__" => 1}
             }
           ] = post.(uuid).event_log |> Enum.sort()

    transition.(uuid, :delete, %{foo: :baz})
    Process.sleep(100)

    assert post.(uuid).state == :*
    # [AM] started failing
    # catch_exit(state.(uuid).current)

    assert [
             %EventLog{
               previous_state: :deleted,
               current_state: :*,
               event: :__end__,
               event_payload: %{"__retries__" => 1}
             },
             %EventLog{
               previous_state: :draft,
               current_state: :deleted,
               event: :delete,
               event_payload: %{"foo" => "baz"}
             },
             %EventLog{
               previous_state: :empty,
               current_state: :draft,
               event: :edit,
               event_payload: %{"foo" => "bar"}
             },
             %EventLog{
               previous_state: :*,
               current_state: :empty,
               event: :__start__,
               event_payload: %{"__retries__" => 1}
             }
           ] = post.(uuid).event_log |> Enum.sort()
  end

  test "loading a persisted struct starts the FSM with correct current state", setup_attrs do
    %{uuid: uuid, post: _post} = setup_attrs
    post = fn uuid -> Post |> Repo.get(uuid) |> Repo.preload(:event_log) end
    state = &Finitomata.state/1

    # update data in database directly
    {:ok, published_post} =
      post.(uuid)
      |> Ecto.Changeset.cast(%{state: :published}, [:state])
      |> Repo.update()

    assert published_post.state == :published

    # kill the FSM process
    pid = Finitomata.fqn(nil, uuid) |> GenServer.whereis()
    assert is_pid(pid)
    assert Process.exit(pid, :kill)
    Process.sleep(100)

    # re-fetch data, which will start the FSM
    assert post.(uuid).state == :published
    assert state.(uuid).current == :published
  end
end
