defmodule MementoMori.EventStore do
  @moduledoc """
  Postgres-backed event store holding the immutable capsule event streams. This
  is the system of record: the audit ledger and the capsule read model are both
  projections of what lives here, never the other way around.
  """
  use EventStore, otp_app: :memento_mori
end
