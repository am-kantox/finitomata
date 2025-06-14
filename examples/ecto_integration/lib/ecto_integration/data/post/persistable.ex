defimpl Finitomata.Persistency.Persistable, for: EctoIntegration.Data.Post do
  @moduledoc """
  Implementation of `Finitomata.Persistency.Persistable` for `Post`.
  """

  require Logger

  alias EctoIntegration.{Data.Post, Data.Post.EventLog, Repo}

  def load(%Post{id: id} = data, _opts \\ []) do
    Post
    |> Repo.get(id)
    |> case do
      %Post{} = post ->
        {:loaded, {post.state, post}}

      nil ->
        new =
          data
          |> Map.from_struct()
          |> Map.take(Post.__schema__(:fields))
          |> Post.new_changeset()
          |> Repo.insert!()

        {:created, {nil, new}}
    end
  end

  def store(
        %Post{id: id} = post,
        %{from: from, to: to, event: event, event_payload: event_payload, object: post}
      ) do
    EventLog.update(
      id,
      %{
        previous_state: from,
        current_state: to,
        event: event,
        event_payload: event_payload
      },
      post
    )
  end

  def store_error(%Post{id: id} = post, reason, %{} = info) do
    metadata = Logger.metadata()

    info
    |> Map.put(:id, id)
    |> Map.put(:data, post)
    |> Map.to_list()
    |> Logger.metadata()

    Logger.warn("[♻️] DB Error: " <> reason)
    Logger.metadata(metadata)
  end
end
