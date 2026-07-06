defmodule MementoMori.VaultTimelockTest do
  @moduledoc """
  Covers the Phase 1 timelock↔capsule integration in the Vault context: binding
  a :date access contract, sealing artifacts to its drand round, and the
  aggregate invariants around sealing.

  Projections are disabled in the test env, so these assert dispatch results and
  the synchronous read-model rows — not the async projected state / audit trail.
  """
  use MementoMori.DataCase

  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Vault
  alias MementoMori.Timelock.Drand

  setup do
    scope = owner_scope_fixture()
    %{scope: scope, capsule: capsule_fixture(scope)}
  end

  describe "set_date_contract/3" do
    test "binds a :date contract whose round matches the unlock time", %{
      scope: scope,
      capsule: capsule
    } do
      assert {:ok, contract} = Vault.set_date_contract(scope, capsule, 3600)

      assert contract.trigger_type == :date
      assert contract.capsule_id == capsule.id
      assert contract.timelock_round > 0
      assert contract.timelock_round == Drand.round_at(contract.embargo_until)
    end

    test "allows only one contract per capsule", %{scope: scope, capsule: capsule} do
      assert {:ok, _} = Vault.set_date_contract(scope, capsule, 3600)
      assert {:error, changeset} = Vault.set_date_contract(scope, capsule, 3600)
      assert %{capsule_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "add_sealed_artifact/3" do
    test "stores ciphertext, captures fixity, and is retrievable", %{
      scope: scope,
      capsule: capsule
    } do
      ciphertext = "-----BEGIN AGE ENCRYPTED FILE-----\nopaque\n-----END-----"

      assert {:ok, artifact} =
               Vault.add_sealed_artifact(scope, capsule, %{
                 "filename" => "letter.txt",
                 "armored_ciphertext" => ciphertext
               })

      assert artifact.filename == "letter.txt"
      assert artifact.capsule_id == capsule.id
      assert artifact.byte_size == byte_size(ciphertext)
      assert artifact.fixity_algorithm == "sha256"
      assert artifact.fixity_digest == Base.encode16(:crypto.hash(:sha256, ciphertext), case: :lower)
      # The operator holds only ciphertext, retrievable for client-side opening.
      assert Vault.read_artifact_ciphertext(artifact) == ciphertext
    end

    test "defaults a blank filename", %{scope: scope, capsule: capsule} do
      assert {:ok, artifact} =
               Vault.add_sealed_artifact(scope, capsule, %{
                 "filename" => "   ",
                 "armored_ciphertext" => "x"
               })

      assert artifact.filename == "message.txt"
    end
  end

  describe "seal_capsule/2" do
    test "seals a draft that holds at least one artifact", %{scope: scope, capsule: capsule} do
      assert {:ok, _} =
               Vault.add_sealed_artifact(scope, capsule, %{
                 "filename" => "a.txt",
                 "armored_ciphertext" => "x"
               })

      assert :ok = Vault.seal_capsule(scope, capsule)
    end

    test "refuses to seal an empty draft", %{scope: scope, capsule: capsule} do
      assert {:error, :nothing_to_seal} = Vault.seal_capsule(scope, capsule)
    end
  end
end
