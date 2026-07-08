defmodule MementoMori.Repo.Migrations.CreateAttestations do
  use Ecto.Migration

  def change do
    create table(:attestations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :text
      add :attested_at, :utc_datetime, null: false
      add :capsule_id, references(:capsules, type: :binary_id, on_delete: :delete_all), null: false
      add :trustee_id, references(:trustees, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # One attestation per trustee per capsule.
    create unique_index(:attestations, [:capsule_id, :trustee_id])
  end
end
