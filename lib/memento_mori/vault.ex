defmodule MementoMori.Vault do
  @moduledoc """
  The Vault context.
  """

  import Ecto.Query, warn: false
  alias MementoMori.Repo

  alias MementoMori.CommandedApp
  alias MementoMori.Timelock.Drand

  alias MementoMori.Vault.{
    AccessContract,
    Artifact,
    ArtifactKind,
    Attestation,
    AuditChain,
    AuditEvent,
    Beneficiary,
    Capsule,
    CiphertextStore,
    Commands,
    Trustee
  }

  alias MementoMori.Accounts
  alias MementoMori.Accounts.Scope

  # The example capsules a new owner lands on — a tour of what actually belongs in
  # a vault, each artifact a different `ArtifactKind`. They're drafts (no contract
  # yet), an invitation to set one. The `note` is stored as the (dev) ciphertext;
  # required template fields must be present or the artifact changeset refuses it.
  @example_capsules [
    %{
      title: "When I'm gone",
      sensitivity_tier: :medium,
      artifacts: [
        %{
          kind: :will,
          filename: "last-will.txt",
          note: "Everything to Dana. She'll know what to do. Good whiskey's behind the books.",
          attributes: %{"executor" => "My sister Dana", "jurisdiction" => "New York"}
        },
        %{
          kind: :letter,
          filename: "for-mom.txt",
          note: "Mom — I made it further than I ever told you. Thank you for all of it.",
          attributes: %{"recipient" => "Mom", "read_when" => "at the funeral"}
        },
        %{
          kind: :loose_ends,
          filename: "cancel-these.txt",
          note: "The gym (lol), three streaming services, that newsletter, the storage unit.",
          attributes: %{"handler" => "Dana"}
        }
      ]
    },
    %{
      title: "The keys to everything",
      # starts low; the secret_key floor ratchets the whole capsule up to high.
      sensitivity_tier: :low,
      artifacts: [
        %{
          kind: :secret_key,
          filename: "password-manager.txt",
          note: "The master password is in your hands now. Try not to lose it like I lose keys.",
          attributes: %{"unlocks" => "1Password (everything else lives in there)"}
        },
        %{
          kind: :secret_key,
          filename: "wallet-seed.txt",
          note: "Twelve words. Do NOT screenshot them. I mean it. Write them down, hide them.",
          attributes: %{"unlocks" => "The Ledger hardware wallet"}
        }
      ]
    },
    %{
      title: "The paperwork nobody can ever find",
      sensitivity_tier: :medium,
      artifacts: [
        %{
          kind: :document,
          filename: "house-deed.txt",
          note: "The deed. Yes, we actually own it. Mostly. The bank owns the rest.",
          attributes: %{"doc_type" => "Deed", "issuer" => "Kings County Clerk"}
        },
        %{
          kind: :document,
          filename: "life-insurance.txt",
          note: "MetLife, policy's in the top drawer. Call them before you call anyone else.",
          attributes: %{"doc_type" => "Life insurance policy", "issuer" => "MetLife"}
        }
      ]
    },
    %{
      title: "For the ones still here",
      sensitivity_tier: :medium,
      artifacts: [
        %{
          kind: :dependent_care,
          filename: "the-cat.txt",
          note: "Miso eats at 7 and 7. He bites. He loves you anyway. Vet is on Union St.",
          attributes: %{"who" => "Miso, the cat"}
        },
        %{
          kind: :letter,
          filename: "to-jordan.txt",
          note: "Jordan — you were the best part. Go outside. Call your mother.",
          attributes: %{"recipient" => "Jordan"}
        }
      ]
    },
    %{
      # A "watch it unlock" example: sealed ~90s into the future, so "Try to open"
      # is refused until the round is emitted, then reveals. `unlock_in_seconds` is
      # read by the seeds sealer; the light placeholder path ignores it.
      title: "Open me on the count of three",
      sensitivity_tier: :low,
      unlock_in_seconds: 90,
      artifacts: [
        %{
          kind: :letter,
          filename: "not-yet.txt",
          note: "If you can read this, the ninety seconds ran out. It felt longer to me.",
          attributes: %{"recipient" => "Whoever clicked too early", "read_when" => "once it opens"}
        }
      ]
    }
  ]

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
  Seeds an owner's example capsules the first time, then never again (guarded by
  `owner.starters_seeded_at`). Safe to call on every visit — a no-op once stamped,
  so a deleted example stays deleted.
  """
  def ensure_starter_capsules(%Scope{owner: %{starters_seeded_at: nil}} = scope) do
    seed_example_capsules(scope)
    Accounts.mark_starters_seeded(scope.owner)
    :ok
  end

  def ensure_starter_capsules(%Scope{}), do: :ok

  @doc "The example capsule specs (data only), for seeding and inspection."
  def example_capsules, do: @example_capsules

  @doc """
  Creates the `@example_capsules` for an owner — each capsule and its artifacts,
  run through the real `create_capsule` / `add_sealed_artifact` paths (so events,
  fixity, and the sensitivity floor all fire). Returns the created capsules.

  `sealer` is `fn artifact, capsule_spec -> ciphertext end` — it turns an
  artifact into the ciphertext to store, given its capsule spec (so it can vary
  the timelock round per capsule, e.g. `unlock_in_seconds`). The default stores
  the note as-is (a dev placeholder that won't decrypt); the seeds script passes a
  real drand-timelock sealer so the blobs actually open. Does not touch the
  seeded-flag; callers decide that.
  """
  def seed_example_capsules(%Scope{} = scope, sealer \\ &default_seal/2) do
    Enum.map(@example_capsules, fn spec ->
      {:ok, capsule} =
        create_capsule(scope, Map.take(spec, [:title, :sensitivity_tier]))

      Enum.each(spec.artifacts, fn artifact ->
        seed_example_artifact(scope, capsule, artifact, sealer.(artifact, spec))
      end)

      capsule
    end)
  end

  defp default_seal(artifact, _spec), do: artifact.note

  defp seed_example_artifact(scope, capsule, artifact, ciphertext) do
    add_sealed_artifact(scope, capsule, %{
      "armored_ciphertext" => ciphertext,
      "filename" => artifact.filename,
      "kind" => to_string(artifact.kind),
      "attributes" => artifact.attributes
    })
  end

  @doc """
  Gets a single capsule.

  Raises `Ecto.NoResultsError` if the Capsule does not exist.

  ## Examples

      iex> get_capsule!(scope, "the-one-with-the-seed-phrase")
      %Capsule{}

      iex> get_capsule!(scope, "a-capsule-that-isnt-yours")
      ** (Ecto.NoResultsError)

  """
  def get_capsule!(%Scope{} = scope, id) do
    Repo.get_by!(Capsule, id: id, owner_id: scope.owner.id)
  end

  @doc """
  Creates a capsule.

  ## Examples

      iex> create_capsule(scope, %{title: "Read this when I'm gone", sensitivity_tier: :high})
      {:ok, %Capsule{}}

      iex> create_capsule(scope, %{title: "", sensitivity_tier: :low})
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

      iex> update_capsule(scope, capsule, %{title: "The wifi password and other final wisdom"})
      {:ok, %Capsule{}}

      iex> update_capsule(scope, capsule, %{sensitivity_tier: :not_a_real_tier})
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

  ## Dead-man's switch
  #
  # The automated counterpart to an owner firing a trigger. A scheduled sweep
  # (`MementoMori.Vault.DeadMansSwitch`) asks for the capsules whose owner has
  # gone silent past their contract's window and fires each one's inactivity
  # trigger. Firing only moves a capsule to `:triggered`; the trustee quorum and
  # cooling-off still gate any real release, so a false silence never releases on
  # its own.

  @doc """
  Sealed `:inactivity` capsules whose owner has been silent (no sign-of-life)
  for at least the contract's `inactivity_threshold_days`. `now` is injected so
  the sweep is deterministically testable. Capsules with no recorded
  `last_sign_of_life_at` (e.g. sealed before the field existed) are excluded —
  the switch needs a clock start to measure from.
  """
  def due_inactivity_capsules(now \\ DateTime.utc_now()) do
    Repo.all(
      from c in Capsule,
        join: ac in AccessContract,
        on: ac.capsule_id == c.id,
        where:
          c.state == :sealed and
            ac.trigger_type == :inactivity and
            not is_nil(ac.inactivity_threshold_days) and
            not is_nil(c.last_sign_of_life_at) and
            datetime_add(c.last_sign_of_life_at, ac.inactivity_threshold_days, "day") < ^now,
        select: c
    )
  end

  @doc """
  Fires a capsule's inactivity trigger as the system (no owner scope) — the
  dead-man's switch, not an owner action. Returns the dispatch result; the
  aggregate guard makes a redundant fire (already triggered) a harmless error.
  """
  def trigger_inactivity(capsule_id) when is_binary(capsule_id) do
    CommandedApp.dispatch(%Commands.FireTrigger{
      capsule_id: capsule_id,
      trigger_type: :inactivity
    })
  end

  ## Access contract, artifacts, and the timelock seal
  #
  # This is where the client-side drand timelock (proven in `MementoMori.Timelock`)
  # meets the capsule domain: a `:date` contract fixes the unlock round, artifacts
  # are sealed to it in the browser, and adding one flows through the aggregate as
  # an `ArtifactAdded` event so the audit ledger records it.

  @doc "Loads a capsule with its access contract, artifacts, trustees, and beneficiaries."
  def get_capsule_with_details!(%Scope{} = scope, id) do
    Capsule
    |> Repo.get_by!(id: id, owner_id: scope.owner.id)
    |> Repo.preload([
      :access_contract,
      :trustees,
      :beneficiaries,
      artifacts: from(a in Artifact, order_by: [asc: a.inserted_at])
    ])
  end

  @doc """
  Binds a pure-time (`:date`) access contract to a draft capsule: the unlock
  instant is turned into the drand round its artifacts will be timelock-sealed to.
  """
  def set_date_contract(%Scope{} = scope, %Capsule{} = capsule, seconds)
      when is_integer(seconds) and seconds > 0 do
    true = capsule.owner_id == scope.owner.id

    unlock_at = DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
    round = Drand.round_at(unlock_at)

    %AccessContract{}
    |> AccessContract.changeset(%{
      trigger_type: :date,
      timelock_round: round,
      embargo_until: unlock_at,
      capsule_id: capsule.id
    })
    |> Repo.insert()
  end

  @doc """
  Records an artifact whose ciphertext was timelock-sealed in the browser. Stores
  the opaque blob, captures a PREMIS-style fixity digest over it, inserts the
  read-model row, and dispatches `AddArtifact` so the event stream (and audit
  ledger) reflect it. Only legal while the capsule is still a draft.
  """
  def add_sealed_artifact(%Scope{} = scope, %Capsule{} = capsule, attrs) do
    true = capsule.owner_id == scope.owner.id

    ciphertext = Map.fetch!(attrs, "armored_ciphertext")
    filename = attrs |> Map.get("filename", "") |> normalize_filename()
    kind = parse_kind(attrs["kind"])
    ref = CiphertextStore.put!(ciphertext)
    artifact_id = Ecto.UUID.generate()
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    artifact_attrs = %{
      kind: kind,
      attributes: Map.get(attrs, "attributes", %{}),
      filename: filename,
      media_type: "text/plain",
      byte_size: byte_size(ciphertext),
      ciphertext_ref: ref,
      fixity_digest: :crypto.hash(:sha256, ciphertext) |> Base.encode16(case: :lower),
      fixity_algorithm: "sha256",
      fixity_checked_at: checked_at,
      provenance_manifest: %{
        "sealed_with" => "drand-timelock-quicknet",
        "sealed_at" => DateTime.to_iso8601(checked_at)
      },
      capsule_id: capsule.id
    }

    with {:ok, artifact} <-
           %Artifact{id: artifact_id}
           |> Artifact.changeset(artifact_attrs)
           |> Repo.insert(),
         {:ok, _capsule} <- raise_sensitivity_floor(scope, capsule, kind),
         :ok <-
           CommandedApp.dispatch(%Commands.AddArtifact{
             capsule_id: capsule.id,
             artifact_id: artifact_id,
             kind: kind,
             filename: filename,
             ciphertext_ref: ref
           }) do
      {:ok, artifact}
    end
  end

  # An artifact's kind sets a *floor* on its capsule's sensitivity: dropping a
  # will or a seed phrase into a `:low` capsule quietly ratchets it up. The owner
  # can raise the tier further, but never back below what its contents demand.
  # sensitivity_tier is owner-facing read-model state (see create_capsule), so we
  # bump the row directly rather than through the aggregate.
  defp raise_sensitivity_floor(%Scope{} = scope, %Capsule{} = capsule, kind) do
    floor = ArtifactKind.sensitivity_floor(kind)
    raised = ArtifactKind.at_least(capsule.sensitivity_tier, floor)

    if raised == capsule.sensitivity_tier do
      {:ok, capsule}
    else
      update_capsule(scope, capsule, %{sensitivity_tier: raised})
    end
  end

  defp parse_kind(nil), do: :generic
  defp parse_kind(kind) when is_atom(kind), do: kind

  defp parse_kind(kind) when is_binary(kind) do
    Enum.find(ArtifactKind.kinds(), :generic, &(to_string(&1) == kind))
  end

  @doc "Reads back an artifact's sealed ciphertext for client-side opening."
  def read_artifact_ciphertext(%Artifact{ciphertext_ref: ref}) do
    case CiphertextStore.get(ref) do
      {:ok, bytes} -> bytes
      _ -> nil
    end
  end

  defp normalize_filename(name) do
    case String.trim(name) do
      "" -> "message.txt"
      trimmed -> trimmed
    end
  end

  ## Trustees, beneficiaries, and the condition (quorum) contract

  @doc """
  Binds a condition-triggered contract (`:death` / `:life_event` / `:inactivity`)
  with an N-of-M trustee quorum. M is the capsule's current trustee count, so
  trustees must be enrolled first.
  """
  def set_condition_contract(%Scope{} = scope, %Capsule{} = capsule, trigger_type, threshold, opts \\ [])
      when trigger_type in [:death, :life_event, :inactivity] and is_integer(threshold) do
    true = capsule.owner_id == scope.owner.id

    size = Repo.aggregate(from(t in Trustee, where: t.capsule_id == ^capsule.id), :count)

    %AccessContract{}
    |> AccessContract.changeset(%{
      trigger_type: trigger_type,
      quorum_threshold: threshold,
      quorum_size: size,
      inactivity_threshold_days: Keyword.get(opts, :inactivity_threshold_days),
      capsule_id: capsule.id
    })
    |> Repo.insert()
  end

  @doc """
  Enrolls a trustee (who attests) on a capsule. Refuses an address already used
  by a beneficiary — a trustee must never also be a beneficiary.
  """
  def add_trustee(%Scope{} = scope, %Capsule{} = capsule, attrs) do
    true = capsule.owner_id == scope.owner.id

    if counterpart?(Beneficiary, capsule.id, attrs) do
      {:error, :already_a_beneficiary}
    else
      %Trustee{}
      |> Trustee.changeset(Map.put(attrs, "capsule_id", capsule.id))
      |> Repo.insert()
    end
  end

  @doc """
  Enrolls a beneficiary (who receives) on a capsule. Refuses an address already
  used by a trustee.
  """
  def add_beneficiary(%Scope{} = scope, %Capsule{} = capsule, attrs) do
    true = capsule.owner_id == scope.owner.id

    if counterpart?(Trustee, capsule.id, attrs) do
      {:error, :already_a_trustee}
    else
      %Beneficiary{}
      |> Beneficiary.changeset(Map.put(attrs, "capsule_id", capsule.id))
      |> Repo.insert()
    end
  end

  # Is the email in `attrs` already enrolled on this capsule in the counterpart
  # role? Looked up by blind index (email_hash), never by plaintext.
  defp counterpart?(schema, capsule_id, attrs) do
    case attrs["email"] do
      email when is_binary(email) and email != "" ->
        Repo.exists?(
          from(x in schema, where: x.capsule_id == ^capsule_id and x.email_hash == ^email)
        )

      _ ->
        false
    end
  end

  ## Capability-gated flows (trustees attest, beneficiaries claim)
  #
  # These functions are reached only after a signed capability token has been
  # verified (see `MementoMoriWeb.CapabilityToken`), so they take a capsule_id +
  # party_id rather than an owner `Scope`: possession of the link is the authority.

  @doc "Loads a trustee and their capsule for the attestation page."
  def get_trustee_context(capsule_id, trustee_id) do
    case Repo.get_by(Trustee, id: trustee_id, capsule_id: capsule_id) do
      nil ->
        :error

      trustee ->
        capsule = Capsule |> Repo.get(capsule_id) |> Repo.preload(:access_contract)

        attested? =
          Repo.exists?(
            from(a in Attestation,
              where: a.capsule_id == ^capsule_id and a.trustee_id == ^trustee_id
            )
          )

        {:ok, %{trustee: trustee, capsule: capsule, attested?: attested?}}
    end
  end

  @doc """
  Records a trustee's attestation (idempotent) and confirms the trustee. The
  quorum is the count of these against the contract threshold.
  """
  def record_attestation(capsule_id, trustee_id, attrs \\ %{}) do
    case Repo.get_by(Trustee, id: trustee_id, capsule_id: capsule_id) do
      nil ->
        {:error, :not_found}

      trustee ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %Attestation{}
        |> Attestation.changeset(%{
          capsule_id: capsule_id,
          trustee_id: trustee_id,
          note: attrs["note"],
          attested_at: now
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:capsule_id, :trustee_id])

        trustee |> Ecto.Changeset.change(status: :confirmed) |> Repo.update()
        {:ok, :recorded}
    end
  end

  @doc "Names of trustees who have attested for a capsule (the real quorum basis)."
  def attested_trustee_names(capsule_id) do
    Repo.all(
      from t in Trustee,
        join: a in Attestation,
        on: a.trustee_id == t.id,
        where: a.capsule_id == ^capsule_id,
        order_by: [asc: t.name],
        select: t.name
    )
  end

  @doc "Loads a beneficiary and their capsule (with artifacts) for the claim portal."
  def get_claim_context(capsule_id, beneficiary_id) do
    case Repo.get_by(Beneficiary, id: beneficiary_id, capsule_id: capsule_id) do
      nil ->
        :error

      beneficiary ->
        capsule =
          Capsule
          |> Repo.get(capsule_id)
          |> Repo.preload([
            :access_contract,
            artifacts: from(a in Artifact, order_by: [asc: a.inserted_at])
          ])

        {:ok, %{beneficiary: beneficiary, capsule: capsule}}
    end
  end

  @doc "Records a beneficiary claiming a released capsule (dispatches ClaimCapsule)."
  def record_beneficiary_claim(capsule_id, beneficiary_id) do
    case Repo.get_by(Beneficiary, id: beneficiary_id, capsule_id: capsule_id) do
      nil ->
        {:error, :not_found}

      beneficiary ->
        with :ok <-
               CommandedApp.dispatch(%Commands.ClaimCapsule{
                 capsule_id: capsule_id,
                 beneficiary_id: beneficiary_id
               }) do
          beneficiary |> Ecto.Changeset.change(status: :claimed) |> Repo.update()
          {:ok, :claimed}
        end
    end
  end

  @doc "Beneficiary consent: defer the inheritance rather than accept it now."
  def defer_beneficiary(capsule_id, beneficiary_id) do
    case Repo.get_by(Beneficiary, id: beneficiary_id, capsule_id: capsule_id) do
      nil -> {:error, :not_found}
      beneficiary -> beneficiary |> Ecto.Changeset.change(status: :deferred) |> Repo.update()
    end
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
