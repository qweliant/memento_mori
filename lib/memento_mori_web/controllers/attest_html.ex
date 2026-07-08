defmodule MementoMoriWeb.AttestHTML do
  @moduledoc """
  Templates for the public trustee attestation page.
  """
  use MementoMoriWeb, :html

  def show(assigns) do
    ~H"""
    <.public_shell flash={@flash}>
      <div class="mb-6 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
        <.icon name="hero-check-badge" class="size-7" />
      </div>
      <h1 class="text-2xl font-semibold tracking-tight">You've been asked to attest</h1>
      <p class="mt-3 text-base-content/70">
        {@trustee.name}, you are a trustee for the capsule
        <span class="font-medium text-base-content">“{@capsule.title}”</span>.
        Attesting means you affirm its trigger condition —
        <span class="font-medium">{@capsule.access_contract && @capsule.access_contract.trigger_type}</span>
        — has genuinely been met. Your attestation joins others toward the required quorum.
      </p>

      <%= if @attested? do %>
        <div class="mt-6 rounded-xl border border-success/30 bg-success/10 px-4 py-3 text-sm text-success">
          You've already attested. Thank you — nothing more is needed.
        </div>
      <% else %>
        <.form :let={_f} for={%{}} action={~p"/attest/#{@token}"} method="post" class="mt-6 text-left">
          <label class="mb-1.5 block text-sm font-medium text-base-content/80">
            A note (optional)
          </label>
          <textarea
            name="note"
            rows="3"
            placeholder="Anything you want on the record about this attestation…"
            class="mb-4 w-full resize-y rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
          ></textarea>
          <button
            type="submit"
            class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-3 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:brightness-110"
          >
            <.icon name="hero-check-circle" class="size-5" /> I attest this is true
          </button>
        </.form>
        <p class="mt-4 text-xs text-base-content/50">
          A trustee only attests — a trustee can never receive the archive.
        </p>
      <% end %>
    </.public_shell>
    """
  end

  def recorded(assigns) do
    ~H"""
    <.public_shell flash={@flash}>
      <div class="mb-6 flex h-14 w-14 items-center justify-center rounded-2xl bg-success/15 text-success">
        <.icon name="hero-check-circle" class="size-7" />
      </div>
      <h1 class="text-2xl font-semibold tracking-tight">Attestation recorded</h1>
      <p class="mt-3 text-base-content/70">
        Thank you. Your attestation has been recorded and counts toward the quorum. You can close
        this page.
      </p>
    </.public_shell>
    """
  end

  def invalid(assigns) do
    ~H"""
    <.public_shell flash={@flash}>
      <div class="mb-6 flex h-14 w-14 items-center justify-center rounded-2xl bg-error/15 text-error">
        <.icon name="hero-exclamation-triangle" class="size-7" />
      </div>
      <h1 class="text-2xl font-semibold tracking-tight">This link isn't valid</h1>
      <p class="mt-3 text-base-content/70">
        The attestation link is invalid or has expired. Ask the capsule's owner for a fresh one.
      </p>
    </.public_shell>
    """
  end

  # Minimal public chrome for token-gated pages — no owner nav, no scope.
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  defp public_shell(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main class="relative mx-auto flex min-h-screen max-w-lg flex-col items-center justify-center px-6 py-16 text-center">
      <div class="absolute top-5 right-5"><Layouts.theme_toggle /></div>
      <div class="w-full rounded-3xl border border-base-300 bg-base-100/70 p-8 shadow-sm backdrop-blur">
        {render_slot(@inner_block)}
      </div>
      <p class="mt-6 text-xs text-base-content/40">Memento Mori · a quiet place for what outlives us</p>
    </main>
    """
  end
end
