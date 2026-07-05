defmodule MementoMori.Vault.Beneficiary do
  @moduledoc """
  A recipient of a capsule. May not yet exist as a user at seal time — they are
  reached at claim time through a capability link and prove possession of a
  claim keypair, to which the content key is re-wrapped on release.

  Beneficiaries hold the right to accept, defer, or delegate an inheritance: the
  `status` tracks that consent so an archive can never ambush someone.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.Capsule

  @statuses [:pending, :notified, :claimed, :deferred, :declined]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "beneficiaries" do
    field :name, :string
    field :email, MementoMori.Encryption.Vault.Binary
    field :email_hash, MementoMori.Encryption.Vault.HashedHMAC
    field :relationship, :string
    # Public half of the claim keypair; release re-wraps the CEK to this.
    field :claim_public_key, :binary
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :capsule, Capsule

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(beneficiary, attrs) do
    beneficiary
    |> cast(attrs, [:name, :email, :relationship, :claim_public_key, :status, :capsule_id])
    |> validate_required([:name, :email, :capsule_id])
    |> put_email_hash()
    |> assoc_constraint(:capsule)
  end

  defp put_email_hash(changeset) do
    case fetch_change(changeset, :email) do
      {:ok, email} -> put_change(changeset, :email_hash, email)
      :error -> changeset
    end
  end
end
