defmodule MementoMori.Repo.Migrations.CreateSealedMessages do
  use Ecto.Migration

  def change do
    create table(:sealed_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string
      # The armored drand-timelock ciphertext. The server stores this opaque blob
      # and cannot read it — the content key is locked to a future drand round.
      add :armored_ciphertext, :text, null: false
      add :unlock_round, :bigint, null: false
      add :unlock_at, :utc_datetime, null: false
      add :opened_at, :utc_datetime
      add :owner_id, references(:owners, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sealed_messages, [:owner_id])
  end
end
