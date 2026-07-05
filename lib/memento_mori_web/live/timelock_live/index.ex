defmodule MementoMoriWeb.TimelockLive.Index do
  @moduledoc """
  The cryptographic heart of the concept, made tangible: seal a message to a
  future moment and watch that even *we* cannot open it until drand says so.

  The plaintext is encrypted in the browser by the `TimelockSeal` hook; only the
  armored ciphertext is pushed to the server. Opening happens in the browser too,
  via `TimelockOpen`, which asks the drand network for the round's key — and is
  refused if that round hasn't happened yet.
  """
  use MementoMoriWeb, :live_view

  alias MementoMori.Timelock

  @durations [
    {"in 30 seconds", 30},
    {"in 2 minutes", 120},
    {"in 10 minutes", 600},
    {"in 1 hour", 3600},
    {"in 1 day", 86_400}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Seal a message")
     |> assign(:durations, @durations)
     |> stream(:messages, Timelock.list_sealed_messages(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("sealed", params, socket) do
    case Timelock.create_sealed_message(socket.assigns.current_scope, params) do
      {:ok, message} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sealed. Locked until #{format_time(message.unlock_at)}.")
         |> stream_insert(:messages, message, at: 0)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not seal that message.")}
    end
  end

  def handle_event("opened", %{"id" => id}, socket) do
    message = Timelock.get_sealed_message!(socket.assigns.current_scope, id)
    {:ok, message} = Timelock.mark_opened(socket.assigns.current_scope, message)
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    message = Timelock.get_sealed_message!(socket.assigns.current_scope, id)
    {:ok, _} = Timelock.delete_sealed_message(socket.assigns.current_scope, message)
    {:noreply, stream_delete(socket, :messages, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <header class="mb-8 text-center">
          <div class="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <.icon name="hero-lock-clock" class="size-7" />
          </div>
          <h1 class="text-2xl font-semibold tracking-tight sm:text-3xl">Seal a message to the future</h1>
          <p class="mx-auto mt-3 max-w-md text-sm leading-6 text-base-content/60">
            Your words are locked on your device to a future moment on the drand clock.
            Until that moment arrives, the ciphertext is all anyone — including us — can see.
          </p>
        </header>

        <%!-- Client-only seal form: the secret never becomes a LiveView field.
              Only the finished ciphertext is pushed to the server. --%>
        <div
          id="seal-form"
          phx-hook="TimelockSeal"
          phx-update="ignore"
          class="rounded-3xl border border-base-300 bg-base-100/70 p-6 shadow-sm backdrop-blur"
        >
          <label class="mb-1.5 block text-sm font-medium text-base-content/80">Label (not secret)</label>
          <input
            data-seal-label
            type="text"
            maxlength="200"
            placeholder="For my daughter, on her 18th"
            class="mb-4 w-full rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
          />

          <label class="mb-1.5 block text-sm font-medium text-base-content/80">Your message</label>
          <textarea
            data-seal-secret
            rows="4"
            placeholder="Write something worth waiting for…"
            class="mb-4 w-full resize-y rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
          ></textarea>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="mb-1.5 block text-sm font-medium text-base-content/80">Unlocks</label>
              <select
                data-seal-duration
                class="w-full rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              >
                <%= for {label, seconds} <- @durations do %>
                  <option value={seconds} selected={seconds == 120}>{label}</option>
                <% end %>
              </select>
            </div>
            <button
              data-seal-submit
              type="button"
              class="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-5 py-2.5 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:brightness-110"
            >
              <.icon name="hero-lock-closed" class="size-4" /> Seal it
            </button>
          </div>
          <p data-seal-status class="mt-3 text-sm text-base-content/60"></p>
        </div>

        <%!-- Sealed messages --%>
        <div class="mt-10">
          <h2 class="mb-4 text-sm font-semibold tracking-wide text-base-content/50 uppercase">
            Your sealed messages
          </h2>
          <div id="messages" phx-update="stream" class="space-y-3">
            <div class="hidden py-10 text-center text-sm text-base-content/50 only:block">
              Nothing sealed yet. Write your first message above.
            </div>

            <div
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class="rounded-2xl border border-base-300 bg-base-100/60 p-5 backdrop-blur"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <p class="truncate font-medium">
                    {if message.label in [nil, ""], do: "Untitled message", else: message.label}
                  </p>
                  <p class="mt-1 flex items-center gap-1.5 text-xs text-base-content/50">
                    <.icon name="hero-clock-micro" class="size-3.5" />
                    Unlocks {format_time(message.unlock_at)} · round {message.unlock_round}
                  </p>
                </div>
                <.status_badge message={message} />
              </div>

              <%!-- ciphertext is not secret; the open hook reads it from here --%>
              <pre id={"ct-#{message.id}"} class="hidden">{message.armored_ciphertext}</pre>

              <div class="mt-4 flex items-center gap-3">
                <button
                  id={"open-#{message.id}"}
                  phx-hook="TimelockOpen"
                  data-id={message.id}
                  data-ciphertext-id={"ct-#{message.id}"}
                  data-target={"#reveal-#{message.id}"}
                  type="button"
                  class="inline-flex items-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3.5 py-2 text-sm font-medium transition hover:bg-base-200"
                >
                  <.icon name="hero-key" class="size-4" /> Try to open
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={message.id}
                  data-confirm="Delete this sealed message?"
                  type="button"
                  class="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-2 text-sm text-base-content/50 transition hover:bg-base-200 hover:text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>

              <div
                id={"reveal-#{message.id}"}
                class="mt-3 hidden rounded-xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm whitespace-pre-wrap"
              >
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :message, :map, required: true

  defp status_badge(assigns) do
    assigns = assign(assigns, :status, unlock_status(assigns.message))

    ~H"""
    <span class={[
      "shrink-0 rounded-full px-3 py-1 text-xs font-medium",
      @status == :sealed && "bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300",
      @status == :ready && "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300",
      @status == :opened && "bg-base-200 text-base-content/60"
    ]}>
      {case @status do
        :sealed -> "🔒 Sealed"
        :ready -> "🔓 Ready"
        :opened -> "Opened"
      end}
    </span>
    """
  end

  defp unlock_status(%{opened_at: %DateTime{}}), do: :opened

  defp unlock_status(message) do
    if DateTime.compare(DateTime.utc_now(), message.unlock_at) == :gt, do: :ready, else: :sealed
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y at %H:%M UTC")
end
