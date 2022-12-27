defimpl Finitomata.Persistency.Persistable, for: EctoIntegration.Data.Post do
  @moduledoc """
  Implementation of `Finitomata.Persistency.Persistable` for `Post`.
  """

  require Logger

  alias EctoIntegration.{Data.Post, Data.Post.EventLog, Repo}

  def load(%Post{} = data, name) do
    Post
    |> Repo.get(name)
    |> case do
      %Post{} = post -> post
      nil -> data |> Map.from_struct() |> Map.take(Post.__schema__(:fields)) |> Map.put(:id, name) |> Post.new_changeset() |> Repo.insert!()
    end
  end

  def store(
        %Post{id: name} = post,
        name,
        {current_state, %Post{id: name} = post},
        {previous_state, event, event_payload, _state_payload}
      ) do
    EventLog.update(
      name,
      %{
        previous_state: previous_state,
        current_state: current_state,
        event: event,
        event_payload: event_payload
      },
      post
    )
  end

  def store_error(data, name, reason, {state, event, event_payload, state_payload}) do
    metadata = Logger.metadata()

    Logger.metadata(
      id: name,
      data: data,
      state: state,
      event: event,
      event_payload: event_payload,
      state_payload: state_payload
    )

    Logger.warn("[DB ERROR]: " <> reason)
    Logger.metadata(metadata)
  end
end
