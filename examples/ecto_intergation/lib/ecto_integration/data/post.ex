defmodule EctoIntegration.Data.Post do
  use Ecto.Schema

  alias Ecto.Changeset
  alias EctoIntegration.Data.{Post, Post.EventLog, Post.FSM}

  @states FSM.states(false)

  @user_fields ~w|title body|a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    field(:title, :string)
    field(:body, :string)
    field(:state, Ecto.Enum, values: @states)

    has_many(:event_log, EventLog)
    timestamps()
  end

  def new_changeset(%{} = params) do
    %Post{state: Finitomata.Transition.entry(FSM.fsm())}
    |> Changeset.cast(params, [:id | @user_fields])
    |> Changeset.validate_required(@user_fields)
    |> Changeset.validate_inclusion(:state, @states)
  end

  def state_update_changeset(%Post{} = post, %{state: _state} = params)
      when map_size(params) == 1 do
    post
    |> Changeset.cast(params, [:state])
    |> Changeset.validate_required([:state])
    |> Changeset.validate_inclusion(:state, @states)
  end

  def update_changeset(%Post{} = post, %{} = params) do
    post
    |> Changeset.cast(params, [:state | @user_fields])
    |> Changeset.validate_inclusion(:state, @states)
  end
end
