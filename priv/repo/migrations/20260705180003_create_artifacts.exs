defmodule MementoMori.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :media_type, :string
      add :byte_size, :bigint
      add :ciphertext_ref, :string, null: false
      add :fixity_digest, :string
      add :fixity_algorithm, :string, default: "sha256"
      add :fixity_checked_at, :utc_datetime
      add :provenance_manifest, :map
      # Owner intent/context, encrypted at rest by Cloak.
      add :envelope, :binary

      add :capsule_id,
          references(:capsules, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:artifacts, [:capsule_id])
  end
end
