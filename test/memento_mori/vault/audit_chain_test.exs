defmodule MementoMori.Vault.AuditChainTest do
  use ExUnit.Case, async: true

  alias MementoMori.Vault.AuditChain

  @capsule_id "22222222-2222-2222-2222-222222222222"

  # Build a valid chain of `n` links, mimicking what the ledger handler writes.
  defp build_chain(events) do
    events
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil}, fn {{type, data}, version}, {rows, prev_hash} ->
      hash = AuditChain.link(prev_hash, @capsule_id, version, type, data)

      row = %{
        capsule_id: @capsule_id,
        stream_version: version,
        event_type: type,
        data: data,
        prev_hash: prev_hash,
        hash: hash
      }

      {[row | rows], hash}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @events [
    {"CapsuleDrafted", %{"title" => "Letters to Maya"}},
    {"ArtifactAdded", %{"filename" => "letter-01.pdf"}},
    {"CapsuleSealed", %{"artifact_count" => 1}}
  ]

  test "the same inputs always hash to the same link" do
    a = AuditChain.link(nil, @capsule_id, 1, "CapsuleDrafted", %{"a" => 1, "b" => 2})
    b = AuditChain.link(nil, @capsule_id, 1, "CapsuleDrafted", %{"b" => 2, "a" => 1})
    assert a == b, "hashing must not depend on map key order"
  end

  test "each link chains onto the previous hash" do
    [first, second, third] = build_chain(@events)

    assert first.prev_hash == nil
    assert second.prev_hash == first.hash
    assert third.prev_hash == second.hash
  end

  test "an intact chain verifies" do
    assert :ok == AuditChain.verify(build_chain(@events))
  end

  test "tampering with a past event's data is detected" do
    [first, second, third] = build_chain(@events)

    # An attacker rewrites the sealed artifact_count but leaves the stored hash.
    forged = %{second | data: %{"filename" => "SOMETHING-ELSE.pdf"}}

    assert {:tampered, 2} == AuditChain.verify([first, forged, third])
  end

  test "dropping a link is detected" do
    [first, _second, third] = build_chain(@events)

    # third.prev_hash points at the removed second link -> break at version 3.
    assert {:tampered, 3} == AuditChain.verify([first, third])
  end

  test "reordering links is detected" do
    [first, second, third] = build_chain(@events)
    # verify sorts by stream_version, so swapping hashes onto wrong versions breaks it.
    swapped = %{second | hash: third.hash}
    assert match?({:tampered, _}, AuditChain.verify([first, swapped, third]))
  end
end
