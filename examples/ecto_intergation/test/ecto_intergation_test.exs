defmodule EctoIntergation.Test do
  use ExUnit.Case
  doctest EctoIntergation

  alias Ecto.Changeset
  alias EctoIntegration.Data.{Post, Post.EventLog, Post.FSM}
  alias EctoIntegration.Repo

  setup_all do
    uuid = Ecto.UUID.generate()
    post = Post.create(%{id: uuid, title: "Post 1", body: "Body 1"})

    %{uuid: uuid, post: post}
  end

  test "`Post` lifecycle", %{uuid: uuid, post: _post} do
    post = fn uuid -> Post |> Repo.get(uuid) |> Repo.preload(:event_log) end
    state = &Finitomata.state/1

    transition = fn uuid, event, payload ->
      Finitomata.transition(uuid, {event, payload})
    end

    assert post.(uuid).state == :empty
    assert state.(uuid).current == :empty

    assert [
             %EventLog{
               previous_state: :*,
               current_state: :empty,
               event: :__start__,
               event_payload: nil
             }
           ] = post.(uuid).event_log

    transition.(uuid, :edit, %{foo: :bar})
    IO.inspect(state.(uuid))

    assert post.(uuid).state == :draft
    assert state.(uuid).current == :draft

    assert [
             %EventLog{
               previous_state: :*,
               current_state: :draft,
               event: :edit,
               event_payload: %{foo: :bar}
             },
             %EventLog{
               previous_state: :*,
               current_state: :empty,
               event: :__start__,
               event_payload: nil
             }
           ] = post.(uuid).event_log
  end
end
