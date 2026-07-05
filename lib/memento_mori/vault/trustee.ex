defmodule MementoMori.Vault.Trustee do
  @moduledoc """
  A named party who *attests* that a capsule's trigger condition has been met —
  deliberately distinct from a beneficiary, who *receives*. Trustees rarely hold
  a full account; they are invited by capability token and act with a keypair
  issued at enrollment. Their attestations count toward the access contract's
  N-of-M quorum, weighted by `weight`.

  Trustee must never equal beneficiary — that separation is what stops a greedy
  heir from both faking the trigger and collecting the archive.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.Capsule

  @statuses [:invited, :confirmed, :revoked]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "trustees" do
    field :name, :string
    field :email, MementoMori.Encryption.Vault.Binary
    field :email_hash, MementoMori.Encryption.Vault.HashedHMAC
    # Public half of the keypair the trustee signs attestations with.
    field :public_key, :binary
    field :weight, :integer, default: 1
    field :status, Ecto.Enum, values: @statuses, default: :invited

    belongs_to :capsule, Capsule

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(trustee, attrs) do
    trustee
    |> cast(attrs, [:name, :email, :public_key, :weight, :status, :capsule_id])
    |> validate_required([:name, :email, :capsule_id])
    |> validate_number(:weight, greater_than: 0)
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
