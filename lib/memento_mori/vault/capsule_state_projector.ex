defmodule MementoMori.Vault.CapsuleStateProjector do
  @moduledoc """
  Mirrors the aggregate's lifecycle onto the `capsules` read model's `state`
  column. This is the *only* writer of `state` — the owner form cannot touch it
  — so what a capsule shows in the UI is always a faithful projection of its
  event stream.
  """
  use Commanded.Event.Handler,
    application: MementoMori.CommandedApp,
    name: __MODULE__,
    start_from: :origin

  alias MementoMori.Repo
  alias MementoMori.Vault.Capsule

  alias MementoMori.Vault.Events.{
    CapsuleDrafted,
    CapsuleSealed,
    SignOfLifeRecorded,
    TriggerFired,
    VerificationOpened,
    CapsuleReleased,
    CapsuleWithheld,
    BeneficiaryClaimed
  }

  @impl Commanded.Event.Handler
  def handle(%CapsuleDrafted{} = e, _meta), do: put_state(e.capsule_id, :draft)

  # Sealing both transitions the read model and starts the dead-man's-switch
  # clock — a freshly sealed capsule is "alive as of now".
  def handle(%CapsuleSealed{} = e, _meta),
    do: patch(e.capsule_id, state: :sealed, last_sign_of_life_at: parse_ts(e.sealed_at))

  # A sign-of-life resets that clock; it carries no state transition.
  def handle(%SignOfLifeRecorded{} = e, _meta),
    do: patch(e.capsule_id, last_sign_of_life_at: parse_ts(e.recorded_at))

  def handle(%TriggerFired{} = e, _meta), do: put_state(e.capsule_id, :triggered)
  def handle(%VerificationOpened{} = e, _meta), do: put_state(e.capsule_id, :verifying)
  def handle(%CapsuleReleased{} = e, _meta), do: put_state(e.capsule_id, :released)
  def handle(%CapsuleWithheld{} = e, _meta), do: put_state(e.capsule_id, :withheld)
  def handle(%BeneficiaryClaimed{} = e, _meta), do: put_state(e.capsule_id, :claimed)

  # Remaining events (artifacts, amendments, threshold) carry no read-model
  # change — the audit ledger still records them.
  def handle(_event, _meta), do: :ok

  defp put_state(capsule_id, state), do: patch(capsule_id, state: state)

  # Applies a set of read-model changes to a capsule row. State goes through the
  # dedicated transition changeset; other system fields are set directly. Both
  # are system-only writers — never reachable from an owner form.
  defp patch(capsule_id, changes) do
    case Repo.get(Capsule, capsule_id) do
      nil ->
        # Read model row not present (e.g. an aggregate seeded outside the
        # owner CRUD path); nothing to project onto.
        :ok

      capsule ->
        {state, rest} = Keyword.pop(changes, :state)

        capsule
        |> maybe_transition(state)
        |> Ecto.Changeset.change(Map.new(rest))
        |> Repo.update!()

        :ok
    end
  end

  defp maybe_transition(capsule, nil), do: Ecto.Changeset.change(capsule)
  defp maybe_transition(capsule, state), do: Capsule.transition_changeset(capsule, state)

  # Event timestamps are ISO8601 strings (see CapsuleAggregate.now/0). A field
  # we can't parse just leaves the clock untouched rather than crashing a sweep.
  defp parse_ts(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_ts(_), do: nil
end
