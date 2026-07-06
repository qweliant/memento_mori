defmodule MementoMori.Repo.Migrations.AddCapsuleSensitivityTierCheck do
  use Ecto.Migration

  def change do
    # Defense-in-depth for data poked in outside Ecto (psql, seeds). Ecto.Enum
    # already guards writes through the app. `state` is intentionally left
    # unconstrained while the capsule state machine is still evolving.
    create constraint(:capsules, :sensitivity_tier_must_be_valid,
             check: "sensitivity_tier IN ('low', 'medium', 'high')"
           )
  end
end
