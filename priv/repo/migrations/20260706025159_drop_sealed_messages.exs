defmodule MementoMori.Repo.Migrations.DropSealedMessages do
  use Ecto.Migration

  # The standalone timelock demo is retired; its mechanism now lives in the real
  # capsule/artifact flow. Drop its table.
  def up do
    drop table(:sealed_messages)
  end

  def down do
    create table(:sealed_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string
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
