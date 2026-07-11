defmodule MementoMori.Vault.ArtifactKind do
  @moduledoc """
  What kind of thing is this artifact, and what does that imply?

  A "template" here is code, not a database row: it declares the kind's
  human label, the sensitivity *floor* it drags a capsule up to, and the
  structured metadata fields an owner fills in. Two hard rules keep this honest:

    1. Bytes stay opaque. The template shapes the *metadata* around a file, never
       the sealed ciphertext itself — that's still an encrypted blob we can't read.
    2. Metadata is NOT a hiding place for secrets. Every field below is
       non-secret provenance ("this is a will", "for the dog"). The actual
       password / seed phrase / spicy confession lives inside the sealed
       ciphertext, which is the only zero-knowledge part. If you ever feel the
       urge to add a `password` field here, go lie down until it passes.

  Adding a kind is a map entry + a test. No migration, no type gymnastics.
  """

  @tiers [:low, :medium, :high]

  # {field_key, label, required?}
  @templates %{
    # The "eh, a file" tier. No ceremony, no floor.
    generic: %{
      label: "Just a file",
      sensitivity_floor: :low,
      release: :deliver,
      fields: []
    },

    # The thing you never said out loud. Non-secret by nature — it's *meant*
    # to be read. The person it's for is the whole point, so it's required.
    letter: %{
      label: "A letter to someone",
      sensitivity_floor: :medium,
      release: :deliver,
      fields: [
        {:recipient, "Addressed to", true},
        {:read_when, "Read this when… (my funeral / you turn 18 / you're sad)", false}
      ]
    },

    # Actual legal weight. High floor because a leaked draft will is a lawsuit.
    will: %{
      label: "Will / final directive",
      sensitivity_floor: :high,
      release: :deliver,
      fields: [
        {:executor, "Executor (the poor soul in charge)", true},
        {:jurisdiction, "Jurisdiction / where I lived", true},
        {:supersedes, "This replaces my earlier will dated…", false}
      ]
    },

    # Deeds, policies, passport scans, the dreaded 1040. Boring, load-bearing.
    document: %{
      label: "Important document",
      sensitivity_floor: :medium,
      release: :deliver,
      fields: [
        {:doc_type, "What is it (deed / policy / 1099 / passport)", true},
        {:issuer, "Issued by", false}
      ]
    },

    # The password-manager master key, the recovery codes, the crypto seed
    # phrase. High floor, and it takes the threshold path: reconstructed from
    # trustee shares, never handed over whole. The key material is in the blob;
    # here we just say what door it opens.
    secret_key: %{
      label: "Vault key / master password / seed phrase",
      sensitivity_floor: :high,
      release: :threshold_reconstruct,
      fields: [
        {:unlocks, "What this unlocks (1Password / the Ledger / my email)", true}
      ]
    },

    # Genuinely the most-requested real feature: "please cancel my stuff." The
    # graveyard shift for your subscriptions. Not secret, extremely useful.
    loose_ends: %{
      label: "Loose ends (accounts to close, subs to cancel)",
      sensitivity_floor: :low,
      release: :deliver,
      fields: [
        {:handler, "Who's cancelling my gym membership from beyond", false}
      ]
    },

    # Someone has to feed the cat. This is not a joke to the cat.
    dependent_care: %{
      label: "Care instructions (pets / plants / people)",
      sensitivity_floor: :medium,
      release: :deliver,
      fields: [
        {:who, "Who / what needs looking after", true}
      ]
    }
  }

  @kinds Map.keys(@templates)

  @doc "Every artifact kind we know how to template."
  def kinds, do: @kinds

  @doc "The full template for a kind."
  def template(kind) when kind in @kinds, do: Map.fetch!(@templates, kind)

  @doc "Human label for a kind."
  def label(kind), do: template(kind).label

  @doc "All metadata field specs `{key, label, required?}` for a kind."
  def fields(kind), do: template(kind).fields

  @doc "Just the required field keys for a kind."
  def required_fields(kind) do
    for {key, _label, true} <- fields(kind), do: key
  end

  @doc "How this kind wants to be released — `:deliver` or `:threshold_reconstruct`."
  def release_strategy(kind), do: template(kind).release

  @doc "The lowest sensitivity tier a capsule may sit at once it holds this kind."
  def sensitivity_floor(kind), do: template(kind).sensitivity_floor

  @doc """
  Raise `current` up to at least `floor` — never lowers. This is the whole
  "template sets a floor the owner can raise but not lower" rule:

      iex> ArtifactKind.at_least(:low, :high)
      :high
      iex> ArtifactKind.at_least(:high, :low)
      :high
  """
  def at_least(current, floor) when current in @tiers and floor in @tiers do
    if tier_rank(floor) > tier_rank(current), do: floor, else: current
  end

  defp tier_rank(tier), do: Enum.find_index(@tiers, &(&1 == tier))
end
