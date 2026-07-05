defmodule MementoMori.CommandedApp do
  @moduledoc """
  The Commanded application: the dispatch + event-store boundary for the capsule
  contract engine. The event-store adapter is configured per environment
  (Postgres `EventStore` in dev/prod, in-memory in test) so the test suite stays
  fast and isolated while dev/prod get a durable, real audit ledger.
  """
  use Commanded.Application, otp_app: :memento_mori

  router(MementoMori.Vault.Router)
end
