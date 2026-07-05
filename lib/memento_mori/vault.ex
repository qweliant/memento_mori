defmodule MementoMori.Vault do
  @moduledoc """
  The Vault context.
  """

  import Ecto.Query, warn: false
  alias MementoMori.Repo

  alias MementoMori.CommandedApp
  alias MementoMori.Vault.{AuditChain, AuditEvent, Capsule, Commands}
  alias MementoMori.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any capsule changes.

  The broadcasted messages match the pattern:

    * {:created, %Capsule{}}
    * {:updated, %Capsule{}}
    * {:deleted, %Capsule{}}

  """
  def subscribe_capsules(%Scope{} = scope) do
    key = scope.owner.id

    Phoenix.PubSub.subscribe(MementoMori.PubSub, "owner:#{key}:capsules")
  end

  defp broadcast_capsule(%Scope{} = scope, message) do
    key = scope.owner.id

    Phoenix.PubSub.broadcast(MementoMori.PubSub, "owner:#{key}:capsules", message)
  end

  @doc """
  Returns the list of capsules.

  ## Examples

      iex> list_capsules(scope)
      [%Capsule{}, ...]

  """
  def list_capsules(%Scope{} = scope) do
    Repo.all_by(Capsule, owner_id: scope.owner.id)
  end

  @doc """
  Gets a single capsule.

  Raises `Ecto.NoResultsError` if the Capsule does not exist.

  ## Examples

      iex> get_capsule!(scope, 123)
      %Capsule{}

      iex> get_capsule!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_capsule!(%Scope{} = scope, id) do
    Repo.get_by!(Capsule, id: id, owner_id: scope.owner.id)
  end

  @doc """
  Creates a capsule.

  ## Examples

      iex> create_capsule(scope, %{field: value})
      {:ok, %Capsule{}}

      iex> create_capsule(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_capsule(%Scope{} = scope, attrs) do
    # Mint the id up front so the read-model row and the aggregate stream share
    # one identity, then seed the event stream with a DraftCapsule so the audit
    # ledger records the capsule from birth.
    capsule_id = Ecto.UUID.generate()

    with {:ok, capsule = %Capsule{}} <-
           %Capsule{id: capsule_id}
           |> Capsule.changeset(attrs, scope)
           |> Repo.insert(),
         :ok <-
           CommandedApp.dispatch(%Commands.DraftCapsule{
             capsule_id: capsule_id,
             owner_id: scope.owner.id,
             title: capsule.title,
             sensitivity_tier: capsule.sensitivity_tier
           }) do
      broadcast_capsule(scope, {:created, capsule})
      {:ok, capsule}
    end
  end

  @doc """
  Updates a capsule.

  ## Examples

      iex> update_capsule(scope, capsule, %{field: new_value})
      {:ok, %Capsule{}}

      iex> update_capsule(scope, capsule, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_capsule(%Scope{} = scope, %Capsule{} = capsule, attrs) do
    true = capsule.owner_id == scope.owner.id

    with {:ok, capsule = %Capsule{}} <-
           capsule
           |> Capsule.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_capsule(scope, {:updated, capsule})
      {:ok, capsule}
    end
  end

  @doc """
  Deletes a capsule.

  ## Examples

      iex> delete_capsule(scope, capsule)
      {:ok, %Capsule{}}

      iex> delete_capsule(scope, capsule)
      {:error, %Ecto.Changeset{}}

  """
  def delete_capsule(%Scope{} = scope, %Capsule{} = capsule) do
    true = capsule.owner_id == scope.owner.id

    with {:ok, capsule = %Capsule{}} <-
           Repo.delete(capsule) do
      broadcast_capsule(scope, {:deleted, capsule})
      {:ok, capsule}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking capsule changes.

  ## Examples

      iex> change_capsule(scope, capsule)
      %Ecto.Changeset{data: %Capsule{}}

  """
  def change_capsule(%Scope{} = scope, %Capsule{} = capsule, attrs \\ %{}) do
    true = capsule.owner_id == scope.owner.id

    Capsule.changeset(capsule, attrs, scope)
  end

  ## Lifecycle commands
  #
  # The capsule's state machine lives in `MementoMori.Vault.CapsuleAggregate`;
  # these functions are the context's typed doorway into it. Each asserts owner
  # scope, then dispatches a command. The resulting state transition is mirrored
  # onto the read model by `CapsuleStateProjector` and recorded (immutably) by
  # `AuditLedger`. State is never mutated here directly.

  @doc "Seal a draft capsule, freezing its artifacts under its access contract."
  def seal_capsule(%Scope{} = scope, %Capsule{} = capsule) do
    dispatch_for(scope, capsule, %Commands.SealCapsule{capsule_id: capsule.id})
  end

  @doc "Record a sign-of-life, resetting the dead-man's-switch on a sealed capsule."
  def record_sign_of_life(%Scope{} = scope, %Capsule{} = capsule) do
    dispatch_for(scope, capsule, %Commands.RecordSignOfLife{capsule_id: capsule.id})
  end

  @doc "Amend a draft or sealed capsule (living amendment)."
  def amend_capsule(%Scope{} = scope, %Capsule{} = capsule, changes) do
    dispatch_for(scope, capsule, %Commands.AmendCapsule{capsule_id: capsule.id, changes: changes})
  end

  @doc "Fire the capsule's trigger, moving it toward verification."
  def fire_trigger(%Scope{} = scope, %Capsule{} = capsule, trigger_type) do
    dispatch_for(scope, capsule, %Commands.FireTrigger{
      capsule_id: capsule.id,
      trigger_type: trigger_type
    })
  end

  @doc "Open the verification case, recording the required N-of-M quorum."
  def open_verification(%Scope{} = scope, %Capsule{} = capsule, threshold, size) do
    dispatch_for(scope, capsule, %Commands.OpenVerification{
      capsule_id: capsule.id,
      quorum_threshold: threshold,
      quorum_size: size
    })
  end

  @doc "Record that the attestation quorum has been met."
  def record_threshold_met(%Scope{} = scope, %Capsule{} = capsule, attestations) do
    dispatch_for(scope, capsule, %Commands.RecordThresholdMet{
      capsule_id: capsule.id,
      attestations: attestations
    })
  end

  @doc "Release a verified capsule to its beneficiaries. Only legal once the quorum is met."
  def release_capsule(%Scope{} = scope, %Capsule{} = capsule) do
    dispatch_for(scope, capsule, %Commands.ReleaseCapsule{capsule_id: capsule.id})
  end

  @doc "Withhold a capsule on doubt — the safe default when a release is uncertain."
  def withhold_capsule(%Scope{} = scope, %Capsule{} = capsule, reason) do
    dispatch_for(scope, capsule, %Commands.WithholdCapsule{capsule_id: capsule.id, reason: reason})
  end

  @doc "Record a beneficiary claiming a released capsule."
  def claim_capsule(%Scope{} = scope, %Capsule{} = capsule, beneficiary_id) do
    dispatch_for(scope, capsule, %Commands.ClaimCapsule{
      capsule_id: capsule.id,
      beneficiary_id: beneficiary_id
    })
  end

  defp dispatch_for(%Scope{} = scope, %Capsule{} = capsule, command) do
    true = capsule.owner_id == scope.owner.id
    CommandedApp.dispatch(command)
  end

  ## Audit ledger (read model)

  @doc """
  Returns the capsule's audit trail, ordered oldest-first — the queryable
  projection of its immutable event stream.
  """
  def list_audit_events(capsule_id) do
    Repo.all(
      from a in AuditEvent,
        where: a.capsule_id == ^capsule_id,
        order_by: [asc: a.stream_version]
    )
  end

  @doc """
  Verify the hash chain of a capsule's audit trail. Returns `:ok` if intact, or
  `{:tampered, stream_version}` at the first broken link.
  """
  def verify_audit_chain(capsule_id) do
    capsule_id
    |> list_audit_events()
    |> AuditChain.verify()
  end
end
