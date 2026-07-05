defmodule MementoMori.Vault.AuditLedger do
  @moduledoc """
  Projects every capsule event into the append-only, hash-chained
  `audit_events` read model. Runs at concurrency 1 so events land in order and
  each row can chain onto the previous one for its capsule without a race.
  """
  use Commanded.Event.Handler,
    application: MementoMori.CommandedApp,
    name: __MODULE__,
    start_from: :origin

  import Ecto.Query, warn: false

  alias MementoMori.Repo
  alias MementoMori.Vault.{AuditChain, AuditEvent}

  @impl Commanded.Event.Handler
  def handle(event, metadata) when is_struct(event) do
    capsule_id = event.capsule_id
    event_type = event.__struct__ |> Module.split() |> List.last()
    data = Map.from_struct(event)

    last = last_link(capsule_id)
    prev_hash = last && last.hash
    stream_version = ((last && last.stream_version) || 0) + 1

    hash = AuditChain.link(prev_hash, capsule_id, stream_version, event_type, data)

    %AuditEvent{
      capsule_id: capsule_id,
      stream_version: stream_version,
      global_sequence: Map.get(metadata, :event_number, 0),
      event_type: event_type,
      data: data,
      prev_hash: prev_hash,
      hash: hash,
      recorded_at: recorded_at(metadata)
    }
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:capsule_id, :stream_version])

    :ok
  end

  defp last_link(capsule_id) do
    Repo.one(
      from a in AuditEvent,
        where: a.capsule_id == ^capsule_id,
        order_by: [desc: a.stream_version],
        limit: 1
    )
  end

  defp recorded_at(%{created_at: %DateTime{} = dt}), do: dt

  defp recorded_at(%{created_at: %NaiveDateTime{} = ndt}),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp recorded_at(_), do: DateTime.utc_now()
end
