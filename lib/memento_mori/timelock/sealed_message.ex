defmodule MementoMori.Timelock.SealedMessage do
  @moduledoc """
  A message the owner sealed to a future moment using drand timelock encryption.

  The plaintext is encrypted **in the browser** and only the armored ciphertext
  ever reaches the server. The content key is locked to a future drand round, so
  neither the operator nor anyone else can read it until that round is published
  by the League of Entropy. This is the zero-knowledge, trustless time-release
  path — the cryptographic heart of a capsule.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sealed_messages" do
    field :label, :string
    field :armored_ciphertext, :string
    field :unlock_round, :integer
    field :unlock_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :owner_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sealed_message, attrs, owner_scope) do
    sealed_message
    |> cast(attrs, [:label, :armored_ciphertext, :unlock_round, :unlock_at])
    |> validate_required([:armored_ciphertext, :unlock_round, :unlock_at])
    |> validate_length(:label, max: 200)
    |> validate_number(:unlock_round, greater_than: 0)
    |> put_change(:owner_id, owner_scope.owner.id)
  end
end
