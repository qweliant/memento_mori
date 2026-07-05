defmodule MementoMori.Repo.Migrations.CreateTrustees do
  use Ecto.Migration

  def change do
    create table(:trustees, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      # Encrypted contact detail + blind index for exact-match lookup.
      add :email, :binary, null: false
      add :email_hash, :binary, null: false
      add :public_key, :binary
      add :weight, :integer, default: 1, null: false
      add :status, :string, default: "invited", null: false

      add :capsule_id,
          references(:capsules, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:trustees, [:capsule_id])
    create index(:trustees, [:email_hash])
  end
end
