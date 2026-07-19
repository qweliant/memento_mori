defmodule MementoMori.Vault.Attestation do
  @moduledoc """
  A trustee's statement that a capsule's trigger condition has been met, made
  through a signed capability link. One per trustee per capsule. When the count
  of attestations reaches the access contract's quorum threshold, release becomes
  reachable — this is the real, trustee-driven basis for the N-of-M quorum.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.{Capsule, Trustee}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attestations" do
    field :note, :string
    field :attested_at, :utc_datetime
    # Raw ECDSA signature (P1363 r||s) over "capsule_id|trustee_id|attested_at",
    # verified against the trustee's pinned public key. Proof of possession.
    field :signature, :binary

    belongs_to :capsule, Capsule
    belongs_to :trustee, Trustee

    timestamps(type: :utc_datetime)
  end

  def changeset(attestation, attrs) do
    attestation
    |> cast(attrs, [:note, :attested_at, :signature, :capsule_id, :trustee_id])
    |> validate_required([:attested_at, :capsule_id, :trustee_id])
    |> assoc_constraint(:capsule)
    |> assoc_constraint(:trustee)
    |> unique_constraint([:capsule_id, :trustee_id])
  end
end
