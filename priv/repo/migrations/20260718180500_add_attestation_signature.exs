defmodule MementoMori.Repo.Migrations.AddAttestationSignature do
  use Ecto.Migration

  def change do
    # The trustee's ECDSA signature over "capsule_id|trustee_id|attested_at",
    # proving possession of the private key pinned on the trustee record.
    alter table(:attestations) do
      add :signature, :binary
    end
  end
end
