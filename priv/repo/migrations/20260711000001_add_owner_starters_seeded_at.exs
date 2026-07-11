defmodule MementoMori.Repo.Migrations.AddOwnerStartersSeededAt do
  use Ecto.Migration

  def change do
    alter table(:owners) do
      # When we seeded this owner's starter capsules. Null = never seeded yet, so
      # they get them on next visit. Set once, so deleting a starter sticks.
      add :starters_seeded_at, :utc_datetime
    end
  end
end
