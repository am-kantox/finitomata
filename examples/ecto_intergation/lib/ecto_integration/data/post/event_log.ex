defmodule EctoIntegration.Data.Post.EventLog do
  use Ecto.Schema

  alias Ecto.{Changeset, Multi}
  alias EctoIntegration.Data.{Post, Post.EventLog, Post.FSM}
  alias EctoIntegration.Repo

  @states FSM.states(true)
  @events FSM.events(true)

  @user_fields ~w|previous_state current_state event post_id|a

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

  @spec store(Ecto.UUID.t(), map()) ::
          {:ok, any}
          | {:error, [{atom(), Changeset.error()}]}
          | {:error, Multi.name(), any(), %{required(Multi.name()) => any()}}
  def store(post_id, %{current_state: state} = params) do
    params
    |> Map.put(:post_id, post_id)
    |> EventLog.changeset()
    |> case do
      %Changeset{valid?: true} = changeset ->
        Multi.new()
        |> Multi.update(
          :post,
          Post.state_update_changeset(Repo.get!(Post, post_id), %{state: state})
        )
        |> Multi.insert(:event_log, changeset)
        |> Repo.transaction()

      %Changeset{errors: errors} ->
        {:error, errors}
    end
  end

  def changeset(%{post_id: post_id} = params) when is_binary(post_id) do
    %EventLog{}
    |> Changeset.cast(params, @user_fields)
    |> IO.inspect(label: "1")
    |> Changeset.validate_required(@user_fields)
    |> IO.inspect(label: "2")
    |> Changeset.validate_inclusion(:previous_state, @states)
    |> IO.inspect(label: "3")
    |> Changeset.validate_inclusion(:current_state, @states)
    |> Changeset.validate_inclusion(:event, @events)
  end
end
