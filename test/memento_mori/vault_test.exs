defmodule MementoMori.VaultTest do
  use MementoMori.DataCase

  alias MementoMori.Vault

  describe "capsules" do
    alias MementoMori.Vault.Capsule

    import MementoMori.AccountsFixtures, only: [owner_scope_fixture: 0]
    import MementoMori.VaultFixtures

    @invalid_attrs %{title: nil, sensitivity_tier: nil}

    test "list_capsules/1 returns all scoped capsules" do
      scope = owner_scope_fixture()
      other_scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      other_capsule = capsule_fixture(other_scope)
      assert Vault.list_capsules(scope) == [capsule]
      assert Vault.list_capsules(other_scope) == [other_capsule]
    end

    test "get_capsule!/2 returns the capsule with given id" do
      scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      other_scope = owner_scope_fixture()
      assert Vault.get_capsule!(scope, capsule.id) == capsule
      assert_raise Ecto.NoResultsError, fn -> Vault.get_capsule!(other_scope, capsule.id) end
    end

    test "create_capsule/2 with valid data creates a capsule in the draft state" do
      valid_attrs = %{title: "Read this when I'm gone", sensitivity_tier: :high}
      scope = owner_scope_fixture()

      assert {:ok, %Capsule{} = capsule} = Vault.create_capsule(scope, valid_attrs)
      # State is system-managed: a fresh capsule is always a draft, never
      # whatever the caller might have tried to set.
      assert capsule.state == :draft
      assert capsule.title == "Read this when I'm gone"
      assert capsule.sensitivity_tier == :high
      assert capsule.owner_id == scope.owner.id
    end

    test "create_capsule/2 ignores any caller-supplied state" do
      scope = owner_scope_fixture()

      assert {:ok, %Capsule{state: :draft}} =
               Vault.create_capsule(scope, %{title: "t", sensitivity_tier: :low, state: :released})
    end

    test "create_capsule/2 with invalid data returns error changeset" do
      scope = owner_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Vault.create_capsule(scope, @invalid_attrs)
    end

    test "update_capsule/3 with valid data updates the capsule" do
      scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      update_attrs = %{title: "The wifi password and other final wisdom", sensitivity_tier: :low}

      assert {:ok, %Capsule{} = capsule} = Vault.update_capsule(scope, capsule, update_attrs)
      assert capsule.title == "The wifi password and other final wisdom"
      assert capsule.sensitivity_tier == :low
    end

    test "update_capsule/3 with invalid scope raises" do
      scope = owner_scope_fixture()
      other_scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)

      assert_raise MatchError, fn ->
        Vault.update_capsule(other_scope, capsule, %{})
      end
    end

    test "update_capsule/3 with invalid data returns error changeset" do
      scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Vault.update_capsule(scope, capsule, @invalid_attrs)
      assert capsule == Vault.get_capsule!(scope, capsule.id)
    end

    test "delete_capsule/2 deletes the capsule" do
      scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      assert {:ok, %Capsule{}} = Vault.delete_capsule(scope, capsule)
      assert_raise Ecto.NoResultsError, fn -> Vault.get_capsule!(scope, capsule.id) end
    end

    test "delete_capsule/2 with invalid scope raises" do
      scope = owner_scope_fixture()
      other_scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      assert_raise MatchError, fn -> Vault.delete_capsule(other_scope, capsule) end
    end

    test "change_capsule/2 returns a capsule changeset" do
      scope = owner_scope_fixture()
      capsule = capsule_fixture(scope)
      assert %Ecto.Changeset{} = Vault.change_capsule(scope, capsule)
    end
  end
end
