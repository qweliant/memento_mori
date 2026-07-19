defmodule MementoMoriWeb.ClaimLive do
  @moduledoc """
  The public beneficiary claim portal. Reached via a signed capability link — no
  account. Once a capsule is released, the named beneficiary can open its
  artifacts (decrypted client-side by drand timelock) and accept, or defer.

  Built as a LiveView rather than a plain controller precisely because opening an
  artifact is client-side crypto (the `TimelockOpen` hook), and consent (accept /
  defer) is interactive.
  """
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault
  alias MementoMoriWeb.CapabilityToken

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case CapabilityToken.verify_beneficiary(token) do
      {:ok, %{capsule_id: capsule_id, beneficiary_id: beneficiary_id}} ->
        {:ok,
         socket
         |> assign(:page_title, "Claim")
         |> assign(:valid?, true)
         |> assign(:capsule_id, capsule_id)
         |> assign(:beneficiary_id, beneficiary_id)
         |> load()}

      _ ->
        {:ok, socket |> assign(:page_title, "Claim") |> assign(:valid?, false)}
    end
  end

  @impl true
  def handle_event("claim", _params, socket) do
    case Vault.record_beneficiary_claim(socket.assigns.capsule_id, socket.assigns.beneficiary_id) do
      {:ok, :claimed} ->
        {:noreply, socket |> put_flash(:info, "You've accepted this inheritance.") |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not accept yet: #{inspect(reason)}")}
    end
  end

  def handle_event("defer", _params, socket) do
    case Vault.defer_beneficiary(socket.assigns.capsule_id, socket.assigns.beneficiary_id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Held for you. Come back when you're ready.") |> load()}
      _ -> {:noreply, put_flash(socket, :error, "Could not defer.")}
    end
  end

  # From the TimelockOpen hook.
  def handle_event("opened", _params, socket), do: {:noreply, socket}

  defp load(socket) do
    case Vault.get_claim_context(socket.assigns.capsule_id, socket.assigns.beneficiary_id) do
      {:ok, ctx} ->
        ciphertexts =
          Map.new(ctx.capsule.artifacts, fn artifact ->
            {artifact.id, Vault.read_artifact_ciphertext(artifact) || ""}
          end)

        socket
        |> assign(:capsule, ctx.capsule)
        |> assign(:beneficiary, ctx.beneficiary)
        |> assign(:ciphertexts, ciphertexts)

      :error ->
        assign(socket, :valid?, false)
    end
  end

  @impl true
  def render(%{valid?: false} = assigns) do
    ~H"""
    <.shell flash={@flash}>
      <div class="mb-6 flex h-14 w-14 items-center justify-center rounded-2xl bg-error/15 text-error">
        <.icon name="hero-exclamation-triangle" class="size-7" />
      </div>
      <h1 class="text-2xl font-semibold tracking-tight">This link isn't valid</h1>
      <p class="mt-3 text-base-content/70">
        This link is invalid or has expired. Ask whoever sent it for a new one.
      </p>
    </.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.shell flash={@flash}>
      <div class="mb-6 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
        <.icon name="hero-gift" class="size-7" />
      </div>
      <h1 class="text-2xl font-semibold tracking-tight">Something was left for you</h1>
      <p class="mt-3 text-base-content/70">
        {@beneficiary.name}, <span class="font-medium text-base-content">“{@capsule.title}”</span>
        was left for you.
      </p>

      <%= if @capsule.state in [:released, :claimed] do %>
        <div class="mt-6 space-y-3 text-left">
          <%= for artifact <- @capsule.artifacts do %>
            <div class="rounded-2xl border border-base-300 bg-base-100/60 p-4">
              <p class="font-medium">{artifact.filename}</p>
              <pre id={"ct-#{artifact.id}"} class="hidden">{Map.get(@ciphertexts, artifact.id, "")}</pre>
              <button
                id={"open-#{artifact.id}"}
                phx-hook="TimelockOpen"
                data-id={artifact.id}
                data-ciphertext-id={"ct-#{artifact.id}"}
                data-target={"#reveal-#{artifact.id}"}
                data-media-type={artifact.media_type}
                data-filename={artifact.filename}
                type="button"
                class="mt-2 inline-flex items-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3.5 py-2 text-sm font-medium transition hover:bg-base-200"
              >
                <.icon name="hero-key" class="size-4" /> Open
              </button>
              <div
                id={"reveal-#{artifact.id}"}
                class="mt-3 hidden rounded-xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm whitespace-pre-wrap"
              >
              </div>
            </div>
          <% end %>
        </div>

        <div class="mt-6">
          <%= if @beneficiary.status == :claimed do %>
            <p class="rounded-xl border border-success/30 bg-success/10 px-4 py-3 text-sm text-success">
              You've accepted this inheritance. It's yours to keep.
            </p>
          <% else %>
            <div class="flex flex-col items-center gap-2 sm:flex-row sm:justify-center">
              <button
                phx-click="claim"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-3 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:brightness-110"
              >
                <.icon name="hero-heart" class="size-5" /> Accept
              </button>
              <button
                phx-click="defer"
                class="rounded-full border border-base-300 px-6 py-3 font-semibold text-base-content/70 transition hover:bg-base-200"
              >
                Not yet, hold for me
              </button>
            </div>
            <p class="mt-4 text-xs text-base-content/50">
              An inheritance shouldn't ambush anyone. Accept whenever you're ready, or hold it for later.
            </p>
          <% end %>
        </div>
      <% else %>
        <div class="mt-6 rounded-xl border border-base-300 bg-base-100/60 px-4 py-3 text-sm text-base-content/60">
          This isn't open yet. It'll be here when the time comes.
        </div>
      <% end %>
    </.shell>
    """
  end

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  defp shell(assigns) do
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
