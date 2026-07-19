defmodule MementoMori.Repo.Migrations.AddDeadMansSwitchFields do
  use Ecto.Migration

  def change do
    # The silence window for an :inactivity contract — how long the owner may go
    # without a sign-of-life before the dead-man's switch fires the trigger.
    alter table(:access_contracts) do
      add :inactivity_threshold_days, :integer
    end

    # Read-model projection of the last SignOfLifeRecorded (seeded at seal). The
    # dead-man's-switch sweep compares this against the contract threshold.
    alter table(:capsules) do
      add :last_sign_of_life_at, :utc_datetime
    end
  end
end
