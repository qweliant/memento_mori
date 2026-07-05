defmodule MementoMori.Vault.AuditEvent do
  @moduledoc """
  A row in the audit ledger read model — one per event in a capsule stream,
  hash-chained to its predecessor. `hash = sha256(prev_hash <> payload)`, so any
  edit or deletion in the chain is detectable. This is the queryable,
  tamper-evident projection of the event store.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :capsule_id, :binary_id
    field :stream_version, :integer
    field :global_sequence, :integer
    field :event_type, :string
    field :data, :map
    field :prev_hash, :string
    field :hash, :string
    field :recorded_at, :utc_datetime_usec
  end
end
