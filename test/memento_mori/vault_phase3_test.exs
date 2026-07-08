defmodule MementoMori.VaultPhase3Test do
  @moduledoc """
  Phase 3: the capability-gated flows — trustee attestation and beneficiary claim.
  """
  use MementoMori.DataCase

  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Vault

  setup do
    scope = owner_scope_fixture()
    capsule = capsule_fixture(scope)
    {:ok, trustee} = Vault.add_trustee(scope, capsule, %{"name" => "Ada", "email" => "ada@example.com"})
    {:ok, beneficiary} = Vault.add_beneficiary(scope, capsule, %{"name" => "Bo", "email" => "bo@example.com"})
    %{scope: scope, capsule: capsule, trustee: trustee, beneficiary: beneficiary}
  end

  describe "record_attestation/3" do
    test "records, confirms the trustee, and is idempotent", %{capsule: c, trustee: t} do
      assert {:ok, :recorded} = Vault.record_attestation(c.id, t.id, %{"note" => "seen"})
      assert Vault.attested_trustee_names(c.id) == ["Ada"]

      assert {:ok, %{trustee: trustee, attested?: true}} = Vault.get_trustee_context(c.id, t.id)
      assert trustee.status == :confirmed

      # second attestation is a no-op, not a duplicate
      assert {:ok, :recorded} = Vault.record_attestation(c.id, t.id)
      assert Vault.attested_trustee_names(c.id) == ["Ada"]
    end

    test "unknown trustee is not_found", %{capsule: c} do
      assert {:error, :not_found} = Vault.record_attestation(c.id, Ecto.UUID.generate())
    end
  end

  describe "context loaders" do
    test "load the party and capsule", %{capsule: c, trustee: t, beneficiary: b} do
      assert {:ok, %{trustee: t2, capsule: cap}} = Vault.get_trustee_context(c.id, t.id)
      assert t2.id == t.id and cap.id == c.id

      assert {:ok, %{beneficiary: b2}} = Vault.get_claim_context(c.id, b.id)
      assert b2.id == b.id
    end

    test "wrong ids error", %{capsule: c} do
      assert :error = Vault.get_trustee_context(c.id, Ecto.UUID.generate())
      assert :error = Vault.get_claim_context(c.id, Ecto.UUID.generate())
    end
  end

  describe "record_beneficiary_claim/2" do
    test "claims once the capsule is released", %{scope: scope, capsule: c, beneficiary: b} do
      {:ok, _} = Vault.set_condition_contract(scope, c, :death, 1)
      {:ok, _} = Vault.add_sealed_artifact(scope, c, %{"filename" => "a.txt", "armored_ciphertext" => "x"})
      :ok = Vault.seal_capsule(scope, c)
      :ok = Vault.fire_trigger(scope, c, :death)
      :ok = Vault.open_verification(scope, c, 1, 1)
      :ok = Vault.record_threshold_met(scope, c, ["Ada"])
      :ok = Vault.release_capsule(scope, c)

      assert {:ok, :claimed} = Vault.record_beneficiary_claim(c.id, b.id)
      assert {:ok, %{beneficiary: b2}} = Vault.get_claim_context(c.id, b.id)
      assert b2.status == :claimed
    end

    test "refuses to claim before release", %{capsule: c, beneficiary: b} do
      assert {:error, {:invalid_state, _}} = Vault.record_beneficiary_claim(c.id, b.id)
    end
  end

  describe "defer_beneficiary/2" do
    test "sets the beneficiary to deferred", %{capsule: c, beneficiary: b} do
      assert {:ok, updated} = Vault.defer_beneficiary(c.id, b.id)
      assert updated.status == :deferred
    end
  end
end
