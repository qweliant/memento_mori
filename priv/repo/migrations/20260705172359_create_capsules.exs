defmodule MementoMori.Repo.Migrations.CreateCapsules do
  use Ecto.Migration

  def change do
    create table(:capsules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :sensitivity_tier, :string
      add :state, :string
      add :owner_id, references(:owners, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:capsules, [:owner_id])
  end
end
