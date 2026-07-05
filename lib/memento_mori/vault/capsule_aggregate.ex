defmodule MementoMori.Vault.CapsuleAggregate do
  @moduledoc """
  The per-capsule contract state machine, as a Commanded aggregate:

      Draft ─seal→ Sealed ─trigger→ Triggered ─open→ Verifying ─┬─release→ Released ─claim→ Claimed
        ↑ amend      ↑ sign-of-life                             └─withhold→ Withheld

  Design invariants drawn from the protocol:

    * Correctness over availability — a false release is catastrophic and
      irreversible, so release is only reachable from `:verifying` *after* the
      quorum threshold has been recorded. Doubt withholds.
    * Sealing requires at least one artifact; an empty capsule cannot be sealed.
    * Living amendment and sign-of-life are self-loops that keep a capsule
      revisable (and its owner demonstrably alive) right up until a trigger.

  `execute/2` is the guard: it returns an event when the transition is legal and
  `{:error, {:invalid_state, status}}` otherwise. `apply/2` folds events back
  into aggregate state.
  """

  alias MementoMori.Vault.CapsuleAggregate

  alias MementoMori.Vault.Commands.{
    DraftCapsule,
    AddArtifact,
    SealCapsule,
    RecordSignOfLife,
    AmendCapsule,
    FireTrigger,
    OpenVerification,
    RecordThresholdMet,
    ReleaseCapsule,
    WithholdCapsule,
    ClaimCapsule
  }

  alias MementoMori.Vault.Events.{
    CapsuleDrafted,
    ArtifactAdded,
    CapsuleSealed,
    SignOfLifeRecorded,
    CapsuleAmended,
    TriggerFired,
    VerificationOpened,
    ThresholdMet,
    CapsuleReleased,
    CapsuleWithheld,
    BeneficiaryClaimed
  }

  defstruct [
    :capsule_id,
    :status,
    :sensitivity_tier,
    :trigger_type,
    artifact_count: 0,
    threshold_met?: false
  ]

  # ── Draft ──────────────────────────────────────────────────────────────────

  def execute(%CapsuleAggregate{status: nil}, %DraftCapsule{} = cmd) do
    %CapsuleDrafted{
      capsule_id: cmd.capsule_id,
      owner_id: cmd.owner_id,
      title: cmd.title,
      sensitivity_tier: cmd.sensitivity_tier,
      drafted_at: now()
    }
  end

  def execute(%CapsuleAggregate{}, %DraftCapsule{}), do: {:error, :already_drafted}

  def execute(%CapsuleAggregate{status: :draft} = agg, %AddArtifact{} = cmd) do
    %ArtifactAdded{
      capsule_id: agg.capsule_id,
      artifact_id: cmd.artifact_id,
      filename: cmd.filename,
      ciphertext_ref: cmd.ciphertext_ref,
      added_at: now()
    }
  end

  def execute(%CapsuleAggregate{status: :draft} = agg, %AmendCapsule{} = cmd) do
    %CapsuleAmended{capsule_id: agg.capsule_id, changes: cmd.changes, amended_at: now()}
  end

  # ── Seal ─────────────────────────────────────────────────────────────────────

  def execute(%CapsuleAggregate{status: :draft, artifact_count: 0}, %SealCapsule{}),
    do: {:error, :nothing_to_seal}

  def execute(%CapsuleAggregate{status: :draft} = agg, %SealCapsule{}) do
    %CapsuleSealed{
      capsule_id: agg.capsule_id,
      artifact_count: agg.artifact_count,
      sealed_at: now()
    }
  end

  # ── Sealed self-loops: sign-of-life & amendment ─────────────────────────────

  def execute(%CapsuleAggregate{status: :sealed} = agg, %RecordSignOfLife{}) do
    %SignOfLifeRecorded{capsule_id: agg.capsule_id, recorded_at: now()}
  end

  def execute(%CapsuleAggregate{status: :sealed} = agg, %AmendCapsule{} = cmd) do
    %CapsuleAmended{capsule_id: agg.capsule_id, changes: cmd.changes, amended_at: now()}
  end

  # ── Trigger ──────────────────────────────────────────────────────────────────

  def execute(%CapsuleAggregate{status: :sealed} = agg, %FireTrigger{} = cmd) do
    %TriggerFired{
      capsule_id: agg.capsule_id,
      trigger_type: cmd.trigger_type,
      fired_at: now()
    }
  end

  # ── Verify ───────────────────────────────────────────────────────────────────

  def execute(%CapsuleAggregate{status: :triggered} = agg, %OpenVerification{} = cmd) do
    %VerificationOpened{
      capsule_id: agg.capsule_id,
      quorum_threshold: cmd.quorum_threshold,
      quorum_size: cmd.quorum_size,
      opened_at: now()
    }
  end

  def execute(%CapsuleAggregate{status: :verifying} = agg, %RecordThresholdMet{} = cmd) do
    %ThresholdMet{capsule_id: agg.capsule_id, attestations: cmd.attestations, met_at: now()}
  end

  # ── Release / Withhold ──────────────────────────────────────────────────────

  def execute(
        %CapsuleAggregate{status: :verifying, threshold_met?: true} = agg,
        %ReleaseCapsule{}
      ) do
    %CapsuleReleased{capsule_id: agg.capsule_id, released_at: now()}
  end

  def execute(%CapsuleAggregate{status: :verifying, threshold_met?: false}, %ReleaseCapsule{}),
    do: {:error, :threshold_not_met}

  # Withholding is always available from a trigger onward — doubt must be able to
  # stop a release at any point before it happens.
  def execute(%CapsuleAggregate{status: status} = agg, %WithholdCapsule{} = cmd)
      when status in [:triggered, :verifying] do
    %CapsuleWithheld{capsule_id: agg.capsule_id, reason: cmd.reason, withheld_at: now()}
  end

  # ── Claim ────────────────────────────────────────────────────────────────────

  def execute(%CapsuleAggregate{status: :released} = agg, %ClaimCapsule{} = cmd) do
    %BeneficiaryClaimed{
      capsule_id: agg.capsule_id,
      beneficiary_id: cmd.beneficiary_id,
      claimed_at: now()
    }
  end

  # ── Catch-all: transition not legal from the current state ──────────────────

  def execute(%CapsuleAggregate{status: status}, _command),
    do: {:error, {:invalid_state, status}}

  # ── State folding ────────────────────────────────────────────────────────────

  def apply(%CapsuleAggregate{} = agg, %CapsuleDrafted{} = e) do
    %{agg | capsule_id: e.capsule_id, status: :draft, sensitivity_tier: e.sensitivity_tier}
  end

  def apply(%CapsuleAggregate{} = agg, %ArtifactAdded{}),
    do: %{agg | artifact_count: agg.artifact_count + 1}

  def apply(%CapsuleAggregate{} = agg, %CapsuleSealed{}), do: %{agg | status: :sealed}
  def apply(%CapsuleAggregate{} = agg, %SignOfLifeRecorded{}), do: agg
  def apply(%CapsuleAggregate{} = agg, %CapsuleAmended{}), do: agg

  def apply(%CapsuleAggregate{} = agg, %TriggerFired{} = e),
    do: %{agg | status: :triggered, trigger_type: e.trigger_type}

  def apply(%CapsuleAggregate{} = agg, %VerificationOpened{}), do: %{agg | status: :verifying}
  def apply(%CapsuleAggregate{} = agg, %ThresholdMet{}), do: %{agg | threshold_met?: true}
  def apply(%CapsuleAggregate{} = agg, %CapsuleReleased{}), do: %{agg | status: :released}
  def apply(%CapsuleAggregate{} = agg, %CapsuleWithheld{}), do: %{agg | status: :withheld}
  def apply(%CapsuleAggregate{} = agg, %BeneficiaryClaimed{}), do: %{agg | status: :claimed}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
