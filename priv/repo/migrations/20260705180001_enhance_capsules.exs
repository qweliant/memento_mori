defmodule MementoMori.Repo.Migrations.EnhanceCapsules do
  use Ecto.Migration

  # `state` and `sensitivity_tier` are Ecto.Enum-backed; they persist as the
  # string form of the atom. Give them sane defaults and forbid nulls now that
  # the lifecycle owns `state`.
  def up do
    execute "UPDATE capsules SET state = 'draft' WHERE state IS NULL"
    execute "UPDATE capsules SET sensitivity_tier = 'low' WHERE sensitivity_tier IS NULL"

    alter table(:capsules) do
      modify :state, :string, default: "draft", null: false
      modify :sensitivity_tier, :string, default: "low", null: false
    end

    create index(:capsules, [:state])
  end

  def down do
    drop index(:capsules, [:state])

    alter table(:capsules) do
      modify :state, :string, default: nil, null: true
      modify :sensitivity_tier, :string, default: nil, null: true
    end
  end
end
