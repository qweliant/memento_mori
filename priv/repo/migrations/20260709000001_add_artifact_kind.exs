defmodule MementoMori.Repo.Migrations.AddArtifactKind do
  use Ecto.Migration

  def change do
    alter table(:artifacts) do
      # What kind of thing this is (see MementoMori.Vault.ArtifactKind).
      # Queryable on purpose: "show me all the wills" shouldn't need a join.
      add :kind, :string, null: false, default: "generic"

      # Non-secret template metadata (executor, jurisdiction, "for the dog").
      # Secrets never live here — they're in the sealed ciphertext.
      add :attributes, :map, null: false, default: %{}
    end

    create index(:artifacts, [:kind])

    # Same defense-in-depth as the capsule sensitivity check: guard rows poked
    # in outside Ecto. Keep this list in sync with ArtifactKind.kinds/0.
    create constraint(:artifacts, :kind_must_be_valid,
             check:
               "kind IN ('generic', 'letter', 'will', 'document', 'secret_key', 'loose_ends', 'dependent_care')"
           )
  end
end
