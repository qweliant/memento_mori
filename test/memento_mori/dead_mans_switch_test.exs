defmodule MementoMori.DeadMansSwitchTest do
  @moduledoc """
  The dead-man's-switch sweep: `Vault.due_inactivity_capsules/1` surfaces exactly
  the sealed `:inactivity` capsules whose owner has gone silent past their
  window. Projections are off in test, so the read-model `state` and
  `last_sign_of_life_at` are seeded directly here rather than through the live
  projector.
  """
  use MementoMori.DataCase

  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Repo
  alias MementoMori.Vault
  alias MementoMori.Vault.{AccessContract, Capsule}

  @now ~U[2026-07-18 00:00:00Z]

  setup do
    %{scope: owner_scope_fixture()}
  end

  defp seal_with(capsule, changes) do
    capsule |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp inactivity_contract(capsule, days) do
    {:ok, contract} =
      %AccessContract{}
      |> AccessContract.changeset(%{
        trigger_type: :inactivity,
        inactivity_threshold_days: days,
        capsule_id: capsule.id
      })
      |> Repo.insert()

    contract
  end

  test "surfaces a capsule silent past its threshold", %{scope: scope} do
    capsule = capsule_fixture(scope)
    inactivity_contract(capsule, 30)
    seal_with(capsule, state: :sealed, last_sign_of_life_at: DateTime.add(@now, -40, :day))

    assert [%Capsule{id: id}] = Vault.due_inactivity_capsules(@now)
    assert id == capsule.id
  end

  test "ignores a capsule still within its window", %{scope: scope} do
    capsule = capsule_fixture(scope)
    inactivity_contract(capsule, 30)
    seal_with(capsule, state: :sealed, last_sign_of_life_at: DateTime.add(@now, -10, :day))

    assert Vault.due_inactivity_capsules(@now) == []
  end

  test "ignores a capsule with no recorded sign-of-life", %{scope: scope} do
    capsule = capsule_fixture(scope)
    inactivity_contract(capsule, 30)
    seal_with(capsule, state: :sealed, last_sign_of_life_at: nil)

    assert Vault.due_inactivity_capsules(@now) == []
  end

  test "ignores non-inactivity triggers even when silent", %{scope: scope} do
    capsule = capsule_fixture(scope)

    {:ok, _} =
      %AccessContract{}
      |> AccessContract.changeset(%{
        trigger_type: :death,
        quorum_threshold: 1,
        quorum_size: 1,
        capsule_id: capsule.id
      })
      |> Repo.insert()

    seal_with(capsule, state: :sealed, last_sign_of_life_at: DateTime.add(@now, -400, :day))

    assert Vault.due_inactivity_capsules(@now) == []
  end

  test "ignores an unsealed (draft) capsule", %{scope: scope} do
    capsule = capsule_fixture(scope)
    inactivity_contract(capsule, 30)
    # left in :draft, but with an old clock
    seal_with(capsule, last_sign_of_life_at: DateTime.add(@now, -400, :day))

    assert Vault.due_inactivity_capsules(@now) == []
  end
end
