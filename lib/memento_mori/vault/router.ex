defmodule MementoMori.Vault.Router do
  @moduledoc """
  Routes capsule commands to the `CapsuleAggregate` instance identified by
  `capsule_id`. Every command in `MementoMori.Vault.Commands` dispatches here.
  """
  use Commanded.Commands.Router

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

  identify(CapsuleAggregate, by: :capsule_id, prefix: "capsule-")

  dispatch(
    [
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
    ],
    to: CapsuleAggregate,
    identity: :capsule_id
  )
end
