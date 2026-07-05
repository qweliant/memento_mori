defmodule MementoMori.Vault.CapsuleAggregateTest do
  @moduledoc """
  Pure state-machine tests: no event store, no processes — just the guard logic
  in `execute/2` and the folding in `apply/2`.
  """
  use ExUnit.Case, async: true

  alias MementoMori.Vault.CapsuleAggregate, as: Agg

  alias MementoMori.Vault.Commands.{
    DraftCapsule,
    AddArtifact,
    SealCapsule,
    RecordSignOfLife,
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
    TriggerFired,
    VerificationOpened,
    ThresholdMet,
    CapsuleReleased,
    CapsuleWithheld,
    BeneficiaryClaimed
  }

  @capsule_id "11111111-1111-1111-1111-111111111111"

  # Fold a command's emitted event back into the aggregate, asserting success.
  defp apply_command(agg, command) do
    event = Agg.execute(agg, command)

    refute match?({:error, _}, event),
           "expected #{inspect(command)} to be allowed, got #{inspect(event)}"

    Agg.apply(agg, event)
  end

  defp drafted do
    Agg.apply(%Agg{}, %CapsuleDrafted{capsule_id: @capsule_id, sensitivity_tier: :high})
  end

  defp sealed do
    drafted()
    |> apply_command(%AddArtifact{capsule_id: @capsule_id, artifact_id: "a1"})
    |> apply_command(%SealCapsule{capsule_id: @capsule_id})
  end

  describe "drafting" do
    test "a fresh aggregate drafts and lands in :draft" do
      agg = apply_command(%Agg{}, %DraftCapsule{capsule_id: @capsule_id, sensitivity_tier: :low})
      assert agg.status == :draft
    end

    test "cannot draft twice" do
      assert {:error, :already_drafted} =
               Agg.execute(drafted(), %DraftCapsule{capsule_id: @capsule_id})
    end
  end

  describe "sealing" do
    test "an empty draft cannot be sealed" do
      assert {:error, :nothing_to_seal} = Agg.execute(drafted(), %SealCapsule{})
    end

    test "a draft with an artifact seals" do
      assert %CapsuleSealed{artifact_count: 1} =
               drafted()
               |> apply_command(%AddArtifact{capsule_id: @capsule_id, artifact_id: "a1"})
               |> Agg.execute(%SealCapsule{})
    end

    test "sign-of-life is a self-loop on a sealed capsule" do
      agg = sealed()

      assert %MementoMori.Vault.Events.SignOfLifeRecorded{} =
               Agg.execute(agg, %RecordSignOfLife{})

      # Still sealed after recording it.
      assert Agg.apply(agg, Agg.execute(agg, %RecordSignOfLife{})).status == :sealed
    end
  end

  describe "release path" do
    test "walks Sealed -> Triggered -> Verifying -> Released -> Claimed" do
      agg =
        sealed()
        |> apply_command(%FireTrigger{capsule_id: @capsule_id, trigger_type: :death})

      assert agg.status == :triggered

      agg =
        agg
        |> apply_command(%OpenVerification{
          capsule_id: @capsule_id,
          quorum_threshold: 2,
          quorum_size: 3
        })

      assert agg.status == :verifying

      # Correctness over availability: cannot release before the quorum is met.
      assert {:error, :threshold_not_met} = Agg.execute(agg, %ReleaseCapsule{})

      agg = apply_command(agg, %RecordThresholdMet{capsule_id: @capsule_id, attestations: 2})
      assert agg.threshold_met?

      agg = apply_command(agg, %ReleaseCapsule{capsule_id: @capsule_id})
      assert agg.status == :released

      agg = apply_command(agg, %ClaimCapsule{capsule_id: @capsule_id, beneficiary_id: "b1"})
      assert agg.status == :claimed
    end
  end

  describe "withhold-on-doubt" do
    test "a triggered capsule can be withheld" do
      agg = sealed() |> apply_command(%FireTrigger{capsule_id: @capsule_id, trigger_type: :death})

      assert %CapsuleWithheld{reason: "registry mismatch"} =
               Agg.execute(agg, %WithholdCapsule{reason: "registry mismatch"})

      assert Agg.apply(agg, Agg.execute(agg, %WithholdCapsule{reason: "x"})).status == :withheld
    end
  end

  describe "illegal transitions" do
    test "cannot fire a trigger on a draft" do
      assert {:error, {:invalid_state, :draft}} =
               Agg.execute(drafted(), %FireTrigger{trigger_type: :death})
    end

    test "cannot claim a capsule that was never released" do
      assert {:error, {:invalid_state, :sealed}} =
               Agg.execute(sealed(), %ClaimCapsule{beneficiary_id: "b1"})
    end
  end

  describe "apply builds the expected shapes" do
    test "artifact count accumulates" do
      agg =
        drafted()
        |> Agg.apply(%ArtifactAdded{})
        |> Agg.apply(%ArtifactAdded{})

      assert agg.artifact_count == 2
    end

    test "trigger type is retained" do
      agg = Agg.apply(sealed(), %TriggerFired{trigger_type: :inactivity})
      assert agg.trigger_type == :inactivity
    end

    test "verification and threshold fold correctly" do
      agg =
        sealed()
        |> Agg.apply(%TriggerFired{trigger_type: :death})
        |> Agg.apply(%VerificationOpened{})
        |> Agg.apply(%ThresholdMet{})

      assert agg.status == :verifying
      assert agg.threshold_met?
    end

    test "release then claim" do
      agg =
        sealed()
        |> Agg.apply(%TriggerFired{trigger_type: :death})
        |> Agg.apply(%VerificationOpened{})
        |> Agg.apply(%CapsuleReleased{})
        |> Agg.apply(%BeneficiaryClaimed{})

      assert agg.status == :claimed
    end
  end
end
