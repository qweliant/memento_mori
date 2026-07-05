defmodule MementoMori.Vault.Commands do
  @moduledoc """
  Intents to change a capsule. Each is routed to `CapsuleAggregate`, which
  decides whether the current state permits it and, if so, emits the
  corresponding event. `capsule_id` is the aggregate identity on every command.
  """

  defmodule DraftCapsule do
    defstruct [:capsule_id, :owner_id, :title, :sensitivity_tier]
  end

  defmodule AddArtifact do
    defstruct [:capsule_id, :artifact_id, :filename, :ciphertext_ref]
  end

  defmodule SealCapsule do
    defstruct [:capsule_id]
  end

  defmodule RecordSignOfLife do
    defstruct [:capsule_id]
  end

  defmodule AmendCapsule do
    defstruct [:capsule_id, :changes]
  end

  defmodule FireTrigger do
    defstruct [:capsule_id, :trigger_type]
  end

  defmodule OpenVerification do
    defstruct [:capsule_id, :quorum_threshold, :quorum_size]
  end

  defmodule RecordThresholdMet do
    defstruct [:capsule_id, :attestations]
  end

  defmodule ReleaseCapsule do
    defstruct [:capsule_id]
  end

  defmodule WithholdCapsule do
    defstruct [:capsule_id, :reason]
  end

  defmodule ClaimCapsule do
    defstruct [:capsule_id, :beneficiary_id]
  end
end
