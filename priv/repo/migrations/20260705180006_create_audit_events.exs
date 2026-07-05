defmodule MementoMori.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  # The audit ledger read model: an append-only projection of the capsule event
  # streams. Each row is hash-chained to the previous row for its capsule
  # (`prev_hash` -> `hash`), making the chain tamper-evident — a Rekor-style
  # transparency log rather than a hand-rolled side table.
  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :capsule_id, :binary_id, null: false
      # Position of this event within its capsule stream (1-based).
      add :stream_version, :integer, null: false
      # Global ordering across all streams, from the event store.
      add :global_sequence, :bigint, null: false
      add :event_type, :string, null: false
      add :data, :map, null: false, default: "{}"
      add :prev_hash, :string
      add :hash, :string, null: false
      add :recorded_at, :utc_datetime_usec, null: false

      # Read model is append-only; no updated_at to imply mutability.
    end

    create unique_index(:audit_events, [:capsule_id, :stream_version])
    create unique_index(:audit_events, [:hash])
    create index(:audit_events, [:global_sequence])
  end
end
