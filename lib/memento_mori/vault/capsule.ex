defmodule MementoMori.Vault.Capsule do
  @moduledoc """
  A sealed unit of legacy — one or more artifacts bound to a single access
  contract. The `state` field is the read-model projection of the capsule's
  event-sourced lifecycle (see `MementoMori.Vault.CapsuleAggregate`); it is
  never set from the owner-facing form. Owners only choose the `title` and the
  `sensitivity_tier`; the state machine owns every transition after that.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.{AccessContract, Artifact, Beneficiary, Trustee}

  @sensitivity_tiers [:low, :medium, :high]
  @states [:draft, :sealed, :triggered, :verifying, :released, :withheld, :claimed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "capsules" do
    field :title, :string
    field :sensitivity_tier, Ecto.Enum, values: @sensitivity_tiers, default: :low
    field :state, Ecto.Enum, values: @states, default: :draft
    field :owner_id, :binary_id
    # System-projected from SignOfLifeRecorded (seeded at seal). Read by the
    # dead-man's-switch sweep; never set from an owner form.
    field :last_sign_of_life_at, :utc_datetime

    has_one :access_contract, AccessContract
    has_many :artifacts, Artifact
    has_many :trustees, Trustee
    has_many :beneficiaries, Beneficiary

    timestamps(type: :utc_datetime)
  end

  @doc """
  Valid sensitivity tiers, lowest bar to highest bar for release.
  """
  def sensitivity_tiers, do: @sensitivity_tiers

  @doc """
  Every lifecycle state the capsule read model can hold.
  """
  def states, do: @states

  @doc """
  Owner-facing changeset. Deliberately excludes `:state` — owners describe the
  capsule and pick its sensitivity, but the lifecycle state is driven only by
  the aggregate/state machine, never by form input.
  """
  def changeset(capsule, attrs, owner_scope) do
    capsule
    |> cast(attrs, [:title, :sensitivity_tier])
    |> validate_required([:title, :sensitivity_tier])
    |> put_change(:owner_id, owner_scope.owner.id)
  end

  @doc """
  System-only changeset used by the state projector to mirror an aggregate
  transition onto the read model. Not reachable from any owner form.
  """
  def transition_changeset(capsule, state) when state in @states do
    change(capsule, state: state)
  end
end
