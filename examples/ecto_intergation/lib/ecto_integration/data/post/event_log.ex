defmodule EctoIntegration.Data.Post.EventLog do
  @moduledoc "Event log backing up `EctoIntegration.Data.Post`"

  use Ecto.Schema

  alias Ecto.{Changeset, Multi}
  alias EctoIntegration.Data.{Post, Post.EventLog, Post.FSM}
  alias EctoIntegration.Repo

  @states FSM.states()
  @events FSM.events()

  @user_fields ~w|post_id previous_state current_state event event_payload|a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "event_logs" do
    field(:previous_state, Ecto.Enum, values: @states)
    field(:current_state, Ecto.Enum, values: @states)
    field(:event, Ecto.Enum, values: @events)
    field(:event_payload, :map)

    belongs_to(:post, Post)

    timestamps()
  end

  @spec update(Ecto.UUID.t(), map(), Post.t()) ::
          {:ok, any}
          | {:error, [{atom(), Changeset.error()}]}
          | {:error, Multi.name(), any(), %{required(Multi.name()) => any()}}
  def update(post_id, %{current_state: state} = params, post) when is_binary(post_id) do
    params
    |> Map.put(:post_id, post_id)
    |> EventLog.changeset()
    |> case do
      %Changeset{valid?: true} = changeset ->
        Multi.new()
        |> Multi.insert(:event_log, changeset)
        |> Multi.update(
          :post,
          Post.update_changeset(
            Repo.get!(Post, post_id),
            post |> Map.take(Post.__schema__(:fields)) |> Map.put(:state, state)
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{post: %Post{} = post}} -> {:ok, post}
          {:error, error} -> {:error, error}
        end

      %Changeset{errors: errors} ->
        {:error, errors}
    end
  end

  def changeset(%{post_id: post_id} = params) when is_binary(post_id) do
    %EventLog{}
    |> Changeset.cast(params, @user_fields)
    |> Changeset.validate_required(@user_fields)
    |> Changeset.validate_inclusion(:previous_state, @states)
    |> Changeset.validate_inclusion(:current_state, @states)
    |> Changeset.validate_inclusion(:event, @events)
  end
end
