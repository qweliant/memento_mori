defmodule MementoMori.Vault.AuditChain do
  @moduledoc """
  Pure hash-chain math for the audit ledger. Kept free of Ecto/Commanded so the
  tamper-evidence property can be reasoned about and tested in isolation.

  Each link's hash commits to the previous link's hash plus this event's
  identifying payload, so altering, reordering, or dropping any past entry breaks
  every hash downstream of it.
  """

  @doc """
  Compute the hash for a new link given the previous link's hash (`nil` for the
  first event in a capsule's chain) and the event's payload fields.
  """
  def link(prev_hash, capsule_id, stream_version, event_type, data) do
    payload =
      [
        prev_hash || "",
        to_string(capsule_id),
        to_string(stream_version),
        to_string(event_type),
        canonical(data)
      ]
      |> Enum.join("|")

    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end

  @doc """
  Recompute the chain over a list of rows ordered by `stream_version` and return
  `:ok` if every stored `hash`/`prev_hash` matches, or `{:tampered, version}` at
  the first divergence. `rows` are maps/structs with the fields written by the
  ledger.
  """
  def verify(rows) do
    rows
    |> Enum.sort_by(& &1.stream_version)
    |> Enum.reduce_while({:ok, nil}, fn row, {:ok, prev_hash} ->
      expected = link(prev_hash, row.capsule_id, row.stream_version, row.event_type, row.data)

      if row.prev_hash == prev_hash and row.hash == expected do
        {:cont, {:ok, row.hash}}
      else
        {:halt, {:tampered, row.stream_version}}
      end
    end)
    |> case do
      {:ok, _last_hash} -> :ok
      other -> other
    end
  end

  # Deterministic serialization of the event payload for hashing: maps become
  # key-sorted pair lists (recursively), so encoding never depends on map order.
  defp canonical(data), do: data |> deep_sort() |> Jason.encode!()

  defp deep_sort(%{__struct__: _} = struct), do: struct |> Map.from_struct() |> deep_sort()

  defp deep_sort(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> [to_string(k), deep_sort(v)] end)
    |> Enum.sort_by(fn [k, _] -> k end)
  end

  defp deep_sort(list) when is_list(list), do: Enum.map(list, &deep_sort/1)
  defp deep_sort(other), do: other
end
