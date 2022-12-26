defmodule EctoIntegration.Repo.Migrations.AddEventLogsTable do
  use Ecto.Migration

  def change do
    create table(:event_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references("posts", type: :binary_id), null: false
      add :previous_state, :string
      add :current_state, :string
      add :event, :string
      add :event_payload, :map

      timestamps()
    end
  end
end
