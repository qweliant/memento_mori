defmodule MementoMori.Repo.Migrations.CreateBeneficiaries do
  use Ecto.Migration

  def change do
    create table(:beneficiaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :binary, null: false
      add :email_hash, :binary, null: false
      add :relationship, :string
      add :claim_public_key, :binary
      add :status, :string, default: "pending", null: false

      add :capsule_id,
          references(:capsules, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:beneficiaries, [:capsule_id])
    create index(:beneficiaries, [:email_hash])
  end
end
