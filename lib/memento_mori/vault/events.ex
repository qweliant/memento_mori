defmodule MementoMori.Vault.Events do
  @moduledoc """
  The immutable facts of a capsule's life. Each is an append-only entry in the
  capsule's event stream; the audit ledger and the read model are both
  projections of these. Structs derive `Jason.Encoder` so the event-store
  serializer can persist them as JSON.
  """

  defmodule CapsuleDrafted do
    @derive Jason.Encoder
    defstruct [:capsule_id, :owner_id, :title, :sensitivity_tier, :drafted_at]
  end

  defmodule ArtifactAdded do
    @derive Jason.Encoder
    defstruct [:capsule_id, :artifact_id, :filename, :ciphertext_ref, :added_at]
  end

  defmodule CapsuleSealed do
    @derive Jason.Encoder
    defstruct [:capsule_id, :artifact_count, :sealed_at]
  end

  defmodule SignOfLifeRecorded do
    @derive Jason.Encoder
    defstruct [:capsule_id, :recorded_at]
  end

  defmodule CapsuleAmended do
    @derive Jason.Encoder
    defstruct [:capsule_id, :changes, :amended_at]
  end

  defmodule TriggerFired do
    @derive Jason.Encoder
    defstruct [:capsule_id, :trigger_type, :fired_at]
  end

  defmodule VerificationOpened do
    @derive Jason.Encoder
    defstruct [:capsule_id, :quorum_threshold, :quorum_size, :opened_at]
  end

  defmodule ThresholdMet do
    @derive Jason.Encoder
    defstruct [:capsule_id, :attestations, :met_at]
  end

  defmodule CapsuleReleased do
    @derive Jason.Encoder
    defstruct [:capsule_id, :released_at]
  end

  defmodule CapsuleWithheld do
    @derive Jason.Encoder
    defstruct [:capsule_id, :reason, :withheld_at]
  end

  defmodule BeneficiaryClaimed do
    @derive Jason.Encoder
    defstruct [:capsule_id, :beneficiary_id, :claimed_at]
  end
end
