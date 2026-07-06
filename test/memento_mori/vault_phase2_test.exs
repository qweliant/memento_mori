defmodule MementoMori.VaultPhase2Test do
  @moduledoc """
  Phase 2: trustee/beneficiary enrollment, the condition (quorum) contract, and
  the full condition lifecycle driven through the aggregate.

  Projections are off in test, so state assertions go through dispatch results
  (the aggregate is authoritative), not the read-model `state` column.
  """
  use MementoMori.DataCase

  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Vault

  setup do
    scope = owner_scope_fixture()
    %{scope: scope, capsule: capsule_fixture(scope)}
  end

  describe "trustees and beneficiaries" do
    test "enrolls trustees and beneficiaries", %{scope: scope, capsule: capsule} do
      assert {:ok, trustee} =
               Vault.add_trustee(scope, capsule, %{"name" => "Ada", "email" => "ada@example.com"})

      assert {:ok, beneficiary} =
               Vault.add_beneficiary(scope, capsule, %{
                 "name" => "Bo",
                 "email" => "bo@example.com",
                 "relationship" => "child"
               })

      assert trustee.name == "Ada"
      assert trustee.status == :invited
      assert beneficiary.relationship == "child"
    end

    test "refuses a beneficiary who is already a trustee (and vice versa)", %{
      scope: scope,
      capsule: capsule
    } do
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "Ada", "email" => "same@example.com"})

      assert {:error, :already_a_trustee} =
               Vault.add_beneficiary(scope, capsule, %{"name" => "Ada", "email" => "same@example.com"})

      {:ok, _} = Vault.add_beneficiary(scope, capsule, %{"name" => "Bo", "email" => "bo@example.com"})

      assert {:error, :already_a_beneficiary} =
               Vault.add_trustee(scope, capsule, %{"name" => "Bo", "email" => "bo@example.com"})
    end
  end

  describe "set_condition_contract/4" do
    test "binds an N-of-M quorum once trustees exist", %{scope: scope, capsule: capsule} do
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "A", "email" => "a@example.com"})
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "B", "email" => "b@example.com"})

      assert {:ok, contract} = Vault.set_condition_contract(scope, capsule, :death, 2)
      assert contract.trigger_type == :death
      assert contract.quorum_threshold == 2
      assert contract.quorum_size == 2
    end

    test "refuses a threshold larger than the trustee count", %{scope: scope, capsule: capsule} do
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "A", "email" => "a@example.com"})
      assert {:error, changeset} = Vault.set_condition_contract(scope, capsule, :death, 3)
      assert %{quorum_threshold: _} = errors_on(changeset)
    end
  end

  describe "condition lifecycle" do
    test "drives seal → trigger → verify → threshold → release → claim", %{
      scope: scope,
      capsule: capsule
    } do
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "A", "email" => "a@example.com"})
      {:ok, ben} = Vault.add_beneficiary(scope, capsule, %{"name" => "Bo", "email" => "bo@example.com"})
      {:ok, _} = Vault.set_condition_contract(scope, capsule, :death, 1)
      {:ok, _} = Vault.add_sealed_artifact(scope, capsule, %{"filename" => "a.txt", "armored_ciphertext" => "x"})

      assert :ok = Vault.seal_capsule(scope, capsule)
      assert :ok = Vault.fire_trigger(scope, capsule, :death)
      assert :ok = Vault.open_verification(scope, capsule, 1, 1)
      assert :ok = Vault.record_threshold_met(scope, capsule, ["A"])
      assert :ok = Vault.release_capsule(scope, capsule)
      assert :ok = Vault.claim_capsule(scope, capsule, ben.id)
    end

    test "refuses release before the quorum threshold is recorded", %{scope: scope, capsule: capsule} do
      {:ok, _} = Vault.add_trustee(scope, capsule, %{"name" => "A", "email" => "a@example.com"})
      {:ok, _} = Vault.set_condition_contract(scope, capsule, :death, 1)
      {:ok, _} = Vault.add_sealed_artifact(scope, capsule, %{"filename" => "a.txt", "armored_ciphertext" => "x"})

      :ok = Vault.seal_capsule(scope, capsule)
      :ok = Vault.fire_trigger(scope, capsule, :death)
      :ok = Vault.open_verification(scope, capsule, 1, 1)

      assert {:error, :threshold_not_met} = Vault.release_capsule(scope, capsule)
    end
  end
end
