defmodule MementoMori.Repo.Migrations.CreateAccessContracts do
  use Ecto.Migration

  def change do
    create table(:access_contracts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :trigger_type, :string, null: false
      add :quorum_threshold, :integer
      add :quorum_size, :integer
      add :cooling_off_days, :integer, default: 0, null: false
      add :embargo_until, :utc_datetime
      add :timelock_round, :bigint
      add :delivery_pacing, :string, default: "immediate", null: false

      add :capsule_id,
          references(:capsules, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    # One contract per capsule.
    create unique_index(:access_contracts, [:capsule_id])
  end
end
