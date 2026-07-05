defmodule MementoMori.Vault.AccessContract do
  @moduledoc """
  The rules that unseal a capsule: the trigger condition, the N-of-M trustee
  quorum, any embargo / timelock, and how release is paced. Exactly one
  contract is bound to each capsule.

  Two release paths, chosen per trigger type:

    * pure `:date` triggers are enforced cryptographically by a timelock round
      (drand / tlock) — no quorum, no operator trust required;
    * `:death`, `:life_event`, and `:inactivity` triggers gather trustee
      attestations until the quorum threshold is met.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.Capsule

  @trigger_types [:death, :date, :life_event, :inactivity]
  @delivery_pacings [:immediate, :drip]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "access_contracts" do
    field :trigger_type, Ecto.Enum, values: @trigger_types
    # N-of-M quorum: `quorum_threshold` (N) of `quorum_size` (M) trustees must attest.
    field :quorum_threshold, :integer
    field :quorum_size, :integer
    # Mandatory waiting window before release; scales with sensitivity tier.
    field :cooling_off_days, :integer, default: 0
    # Event/embargo-locked capsules: nothing releases before this instant.
    field :embargo_until, :utc_datetime
    # Pure time capsules: drand round the content key is timelock-encrypted to.
    field :timelock_round, :integer
    field :delivery_pacing, Ecto.Enum, values: @delivery_pacings, default: :immediate

    belongs_to :capsule, Capsule

    timestamps(type: :utc_datetime)
  end

  def trigger_types, do: @trigger_types
  def delivery_pacings, do: @delivery_pacings

  def changeset(access_contract, attrs) do
    access_contract
    |> cast(attrs, [
      :trigger_type,
      :quorum_threshold,
      :quorum_size,
      :cooling_off_days,
      :embargo_until,
      :timelock_round,
      :delivery_pacing,
      :capsule_id
    ])
    |> validate_required([:trigger_type, :capsule_id])
    |> validate_number(:cooling_off_days, greater_than_or_equal_to: 0)
    |> validate_quorum()
    |> validate_timelock()
    |> assoc_constraint(:capsule)
    |> unique_constraint(:capsule_id)
  end

  # Quorum only applies to attestation-based triggers; when present, N must be
  # a positive number no greater than M.
  defp validate_quorum(changeset) do
    threshold = get_field(changeset, :quorum_threshold)
    size = get_field(changeset, :quorum_size)

    cond do
      is_nil(threshold) and is_nil(size) ->
        changeset

      is_nil(threshold) or is_nil(size) ->
        add_error(changeset, :quorum_threshold, "quorum needs both a threshold and a size")

      threshold < 1 ->
        add_error(changeset, :quorum_threshold, "must be at least 1")

      threshold > size ->
        add_error(changeset, :quorum_threshold, "cannot exceed the number of trustees")

      true ->
        changeset
    end
  end

  # A pure time capsule must carry a timelock round; other triggers must not.
  defp validate_timelock(changeset) do
    case get_field(changeset, :trigger_type) do
      :date ->
        validate_required(changeset, [:timelock_round])

      _ ->
        changeset
    end
  end
end
