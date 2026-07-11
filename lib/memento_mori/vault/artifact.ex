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

  alias MementoMori.Vault.{Capsule, ArtifactKind}

  @kinds ArtifactKind.kinds()

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "artifacts" do
    # What kind of thing this is; drives its template, release path, and the
    # sensitivity floor it imposes on its capsule. See `ArtifactKind`.
    field :kind, Ecto.Enum, values: @kinds, default: :generic
    # Non-secret template metadata (executor, jurisdiction, "for the dog").
    field :attributes, :map, default: %{}

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
      :kind,
      :attributes,
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
    |> validate_required([:kind, :filename, :ciphertext_ref, :capsule_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> validate_kind_fields()
    |> assoc_constraint(:capsule)
  end

  # The whole "type system" for template metadata: a fold over the kind's
  # required fields, run once at the edge. No generics, no guards — the template
  # is the source of truth, `kind` is just the pointer into it.
  defp validate_kind_fields(changeset) do
    kind = get_field(changeset, :kind) || :generic
    attributes = get_field(changeset, :attributes) || %{}

    Enum.reduce(ArtifactKind.required_fields(kind), changeset, fn key, cs ->
      if blank?(fetch_attribute(attributes, key)) do
        {_key, label, _req} = List.keyfind(ArtifactKind.fields(kind), key, 0)
        add_error(cs, :attributes, "#{label} is required for a #{ArtifactKind.label(kind)}")
      else
        cs
      end
    end)
  end

  # Attributes may arrive with atom keys (internal) or string keys (form params).
  defp fetch_attribute(attributes, key) do
    Map.get(attributes, key) || Map.get(attributes, to_string(key))
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
