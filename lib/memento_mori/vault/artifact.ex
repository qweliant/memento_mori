defmodule MementoMori.Vault.Artifact do
  @moduledoc """
  A single file inside a capsule. The operator only ever holds ciphertext: the
  bytes live in Files.com under `ciphertext_ref`, encrypted client-side before
  upload. What we store here is preservation and provenance metadata modeled on
  OAIS / PREMIS — a fixity record `{digest, algorithm, checked_at}` and a
  C2PA-style provenance manifest — plus the owner's `envelope`: the intent and
  context ("why I'm giving you this") that a bare file can never carry. The
  envelope is encrypted at rest with Cloak.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MementoMori.Vault.Capsule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "artifacts" do
    field :filename, :string
    field :media_type, :string
    field :byte_size, :integer
    # Opaque pointer to the ciphertext object in Files.com. Never plaintext.
    field :ciphertext_ref, :string

    # PREMIS-style fixity: proof the bytes have not rotted or been altered.
    field :fixity_digest, :string
    field :fixity_algorithm, :string, default: "sha256"
    field :fixity_checked_at, :utc_datetime

    # C2PA-style signed provenance manifest (chain of custody for the bytes).
    field :provenance_manifest, :map

    # Owner-authored intent/context — encrypted at rest.
    field :envelope, MementoMori.Encryption.Vault.Binary

    belongs_to :capsule, Capsule

    timestamps(type: :utc_datetime)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :filename,
      :media_type,
      :byte_size,
      :ciphertext_ref,
      :fixity_digest,
      :fixity_algorithm,
      :fixity_checked_at,
      :provenance_manifest,
      :envelope,
      :capsule_id
    ])
    |> validate_required([:filename, :ciphertext_ref, :capsule_id])
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> assoc_constraint(:capsule)
  end
end
