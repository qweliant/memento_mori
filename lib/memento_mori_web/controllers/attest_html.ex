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
      <h1 class="text-2xl font-semibold tracking-tight">You've been asked to confirm something</h1>
      <p class="mt-3 text-base-content/70">
        {@trustee.name}, <span class="font-medium text-base-content">“{@capsule.title}”</span>
        picked you as someone they trust. They asked you to confirm that the moment they set has
        actually come. Once enough of their trusted people do, the capsule opens for whoever they
        left it to.
      </p>

      <%= if @attested? do %>
        <div class="mt-6 rounded-xl border border-success/30 bg-success/10 px-4 py-3 text-sm text-success">
          You've already confirmed. Thanks. There's nothing more to do.
        </div>
      <% else %>
        <.form :let={_f} for={%{}} action={~p"/attest/#{@token}"} method="post" class="mt-6 text-left">
          <label class="mb-1.5 block text-sm font-medium text-base-content/80">
            Add a note (optional)
          </label>
          <textarea
            name="note"
            rows="3"
            placeholder="Anything you'd like to leave on the record."
            class="mb-4 w-full resize-y rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
          ></textarea>
          <button
            type="submit"
            class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-3 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:brightness-110"
          >
            <.icon name="hero-check-circle" class="size-5" /> Yes, I confirm
          </button>
        </.form>
        <p class="mt-4 text-xs text-base-content/50">
          You're only here to confirm. You'll never be asked to receive anything.
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
      <h1 class="text-2xl font-semibold tracking-tight">Thank you</h1>
      <p class="mt-3 text-base-content/70">
        Your confirmation has been recorded. You can close this page now.
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
        This link is invalid or has expired. Ask the person who sent it for a new one.
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
      <p class="mt-6 text-xs text-base-content/40">Memento Mori · for the people you love</p>
    </main>
    """
  end
end
