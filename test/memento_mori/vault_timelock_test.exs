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

    test "a text note defaults to text/plain and armored-size", %{scope: scope, capsule: capsule} do
      ciphertext = "-----BEGIN AGE ENCRYPTED FILE-----\nopaque\n-----END-----"

      assert {:ok, artifact} =
               Vault.add_sealed_artifact(scope, capsule, %{
                 "filename" => "note.txt",
                 "armored_ciphertext" => ciphertext
               })

      assert artifact.media_type == "text/plain"
      assert artifact.byte_size == byte_size(ciphertext)
    end

    test "a file keeps its media type and original plaintext size", %{scope: scope, capsule: capsule} do
      # The armored ciphertext is larger than the original; byte_size must reflect
      # the file the owner chose, not the encrypted blob.
      ciphertext = String.duplicate("ARMORED", 500)

      assert {:ok, artifact} =
               Vault.add_sealed_artifact(scope, capsule, %{
                 "filename" => "scan.pdf",
                 "armored_ciphertext" => ciphertext,
                 "media_type" => "application/pdf",
                 # arrives as a string from the JS payload
                 "byte_size" => "2048"
               })

      assert artifact.media_type == "application/pdf"
      assert artifact.byte_size == 2048
      refute artifact.byte_size == byte_size(ciphertext)
      assert Vault.read_artifact_ciphertext(artifact) == ciphertext
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
