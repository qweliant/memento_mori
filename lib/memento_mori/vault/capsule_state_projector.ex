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
    TriggerFired,
    VerificationOpened,
    CapsuleReleased,
    CapsuleWithheld,
    BeneficiaryClaimed
  }

  @impl Commanded.Event.Handler
  def handle(%CapsuleDrafted{} = e, _meta), do: put_state(e.capsule_id, :draft)
  def handle(%CapsuleSealed{} = e, _meta), do: put_state(e.capsule_id, :sealed)
  def handle(%TriggerFired{} = e, _meta), do: put_state(e.capsule_id, :triggered)
  def handle(%VerificationOpened{} = e, _meta), do: put_state(e.capsule_id, :verifying)
  def handle(%CapsuleReleased{} = e, _meta), do: put_state(e.capsule_id, :released)
  def handle(%CapsuleWithheld{} = e, _meta), do: put_state(e.capsule_id, :withheld)
  def handle(%BeneficiaryClaimed{} = e, _meta), do: put_state(e.capsule_id, :claimed)

  # Events that carry no state transition (artifacts, sign-of-life, amendments,
  # threshold) are ignored here — the audit ledger still records them.
  def handle(_event, _meta), do: :ok

  defp put_state(capsule_id, state) do
    case Repo.get(Capsule, capsule_id) do
      nil ->
        # Read model row not present (e.g. an aggregate seeded outside the
        # owner CRUD path); nothing to project onto.
        :ok

      capsule ->
        capsule
        |> Capsule.transition_changeset(state)
        |> Repo.update!()

        :ok
    end
  end
end
