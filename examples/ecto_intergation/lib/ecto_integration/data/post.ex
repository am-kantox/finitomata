defmodule EctoIntegration.Data.Post do
  @moduledoc "Ecto Schema for the FSM-baked entity"
  use Ecto.Schema

  alias Ecto.Changeset
  alias EctoIntegration.Data.{Post, Post.EventLog, Post.FSM}

  @type t :: Ecto.Schema.schema()

  @states FSM.states()

  @user_fields ~w|title body|a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    field(:title, :string)
    field(:body, :string)
    field(:state, Ecto.Enum, values: @states, default: :*)

    has_many(:event_log, EventLog)
    timestamps()
  end

  def new_changeset(%{} = params) do
    %Post{}
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

  def create(%{} = params) do
    {id, post} = Map.pop(params, :id, Ecto.UUID.generate())
    post = Map.put_new(post, :id, id)
    Finitomata.start_fsm(FSM, id, struct!(Post, post))
  end

  def find(id) do
    Finitomata.state(id)
  end
end
