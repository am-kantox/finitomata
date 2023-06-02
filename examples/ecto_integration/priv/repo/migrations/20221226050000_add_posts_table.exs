defmodule EctoIntegration.Repo.Migrations.AddPostsTable do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :body, :string
      add :state, :string

      timestamps()
    end
  end
end
