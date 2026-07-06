defmodule MementoMoriWeb.CapsuleLive.Show do
  @moduledoc """
  The capsule console. Draft a capsule, give it an access contract (a timelock
  date, or a condition with an N-of-M trustee quorum), seal artifacts to it,
  enroll trustees and beneficiaries, then drive the whole lifecycle —
  seal → trigger → verify → release → claim — through the aggregate. Every step
  lands in the hash-chained audit ledger at the bottom.

  Sealing/opening artifacts is client-side drand timelock; the lifecycle actions
  dispatch commands whose legality the aggregate enforces.
  """
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault
  alias MementoMori.Vault.Capsule

  @durations [
    {"in 30 seconds", 30},
    {"in 2 minutes", 120},
    {"in 10 minutes", 600},
    {"in 1 hour", 3600},
    {"in 1 day", 86_400}
  ]

  @trigger_atoms %{"death" => :death, "life_event" => :life_event, "inactivity" => :inactivity}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@capsule.title}
        <:subtitle><.state_badge state={@capsule.state} /></:subtitle>
        <:actions>
          <.button navigate={~p"/capsules"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
          <.button variant="primary" navigate={~p"/capsules/#{@capsule}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@capsule.title}</:item>
        <:item title="Sensitivity tier">{@capsule.sensitivity_tier}</:item>
        <:item title="State"><.state_badge state={@capsule.state} /></:item>
      </.list>

      <%!-- ── Access contract ──────────────────────────────────────────────── --%>
      <.section icon="hero-clock" title="Unlock">
        <%= cond do %>
          <% @capsule.access_contract -> %>
            <div class="rounded-2xl border border-base-300 bg-base-100/60 p-5">
              <p class="font-medium">{contract_summary(@capsule.access_contract)}</p>
              <p class="mt-1 text-sm text-base-content/60">
                Trigger: {@capsule.access_contract.trigger_type}<%= if @capsule.access_contract.timelock_round do %>
                  · drand round {@capsule.access_contract.timelock_round}
                <% end %><%= if @capsule.access_contract.quorum_threshold do %>
                  · quorum {@capsule.access_contract.quorum_threshold}-of-{@capsule.access_contract.quorum_size}
                <% end %>
              </p>
            </div>
          <% @capsule.state == :draft -> %>
            <div class="grid gap-4 sm:grid-cols-2">
              <form phx-submit="set_date_contract" class="rounded-2xl border border-base-300 bg-base-100/60 p-5">
                <p class="mb-1 font-medium">A specific time</p>
                <p class="mb-3 text-sm text-base-content/60">Cryptographically enforced by drand — trustless.</p>
                <select
                  name="seconds"
                  class="mb-3 w-full rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
                >
                  <%= for {label, seconds} <- @durations do %>
                    <option value={seconds} selected={seconds == 120}>{label}</option>
                  <% end %>
                </select>
                <.button variant="primary">Time-lock it</.button>
              </form>

              <form phx-submit="set_condition_contract" class="rounded-2xl border border-base-300 bg-base-100/60 p-5">
                <p class="mb-1 font-medium">A condition</p>
                <p class="mb-3 text-sm text-base-content/60">
                  Released after trustees attest ({@trustee_count} enrolled).
                </p>
                <div class="mb-3 flex gap-2">
                  <select
                    name="trigger_type"
                    class="flex-1 rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-sm"
                  >
                    <option value="death">After I'm gone</option>
                    <option value="life_event">A life event</option>
                    <option value="inactivity">Inactivity</option>
                  </select>
                  <input
                    name="threshold"
                    type="number"
                    min="1"
                    value="1"
                    class="w-24 rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-sm"
                  />
                </div>
                <.button variant="primary">Set quorum</.button>
                <p :if={@trustee_count == 0} class="mt-2 text-xs text-amber-600">
                  Enroll trustees below first.
                </p>
              </form>
            </div>
          <% true -> %>
            <p class="text-sm text-base-content/50">No access contract was set before sealing.</p>
        <% end %>
      </.section>

      <%!-- ── Seal an artifact ─────────────────────────────────────────────── --%>
      <%= if @capsule.state == :draft and @capsule.access_contract && @capsule.access_contract.timelock_round do %>
        <.section icon="hero-lock-closed" title="Seal an artifact">
          <div
            id="capsule-seal"
            phx-hook="CapsuleSeal"
            phx-update="ignore"
            data-round={@capsule.access_contract.timelock_round}
            class="rounded-2xl border border-base-300 bg-base-100/60 p-5"
          >
            <input
              data-seal-filename
              type="text"
              placeholder="letter.txt"
              class="mb-3 w-full rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
            />
            <textarea
              data-seal-note
              rows="3"
              placeholder="Write the message to seal to the future…"
              class="mb-3 w-full resize-y rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
            ></textarea>
            <div class="flex items-center gap-3">
              <button
                data-seal-submit
                type="button"
                class="inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:brightness-110"
              >
                <.icon name="hero-lock-closed" class="size-4" /> Seal to the future
              </button>
              <p data-seal-status class="text-sm text-base-content/60"></p>
            </div>
          </div>
        </.section>
      <% end %>

      <%!-- ── Artifacts ────────────────────────────────────────────────────── --%>
      <.section icon="hero-document-text" title={"Artifacts (#{@artifact_count})"}>
        <%= if @artifact_count == 0 do %>
          <p class="text-sm text-base-content/50">Nothing sealed into this capsule yet.</p>
        <% else %>
          <div class="space-y-3">
            <%= for artifact <- @capsule.artifacts do %>
              <div class="rounded-2xl border border-base-300 bg-base-100/60 p-5">
                <p class="truncate font-medium">{artifact.filename}</p>
                <p class="mt-1 font-mono text-xs text-base-content/40">
                  {artifact.byte_size} bytes · sha256 {String.slice(artifact.fixity_digest || "", 0, 16)}…
                </p>
                <pre id={"ct-#{artifact.id}"} class="hidden">{Map.get(@ciphertexts, artifact.id, "")}</pre>
                <div class="mt-3">
                  <button
                    id={"open-#{artifact.id}"}
                    phx-hook="TimelockOpen"
                    data-id={artifact.id}
                    data-ciphertext-id={"ct-#{artifact.id}"}
                    data-target={"#reveal-#{artifact.id}"}
                    type="button"
                    class="inline-flex items-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3.5 py-2 text-sm font-medium transition hover:bg-base-200"
                  >
                    <.icon name="hero-key" class="size-4" /> Try to open
                  </button>
                </div>
                <div
                  id={"reveal-#{artifact.id}"}
                  class="mt-3 hidden rounded-xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm whitespace-pre-wrap"
                >
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @capsule.state == :draft and @artifact_count > 0 do %>
          <div class="mt-4">
            <.button
              phx-click="seal_capsule"
              variant="primary"
              data-confirm="Seal this capsule? Its artifacts freeze under the access contract."
            >
              <.icon name="hero-lock-closed" /> Seal capsule
            </.button>
          </div>
        <% end %>
      </.section>

      <%!-- ── Trustees ─────────────────────────────────────────────────────── --%>
      <.section icon="hero-user-group" title={"Trustees (#{@trustee_count})"}>
        <div class="space-y-2">
          <div :for={t <- @capsule.trustees} class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100/50 px-4 py-2.5 text-sm">
            <span class="font-medium">{t.name}</span>
            <span class="rounded-full bg-base-200 px-2 py-0.5 text-xs text-base-content/60">{t.status}</span>
            <span class="ml-auto text-xs text-base-content/40">weight {t.weight}</span>
          </div>
        </div>
        <%= if @capsule.state in [:draft, :sealed] do %>
          <form phx-submit="add_trustee" class="mt-3 flex flex-col gap-2 sm:flex-row">
            <input name="name" placeholder="Name" required class="flex-1 rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm" />
            <input name="email" type="email" placeholder="email" required class="flex-1 rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm" />
            <.button variant="primary">Add trustee</.button>
          </form>
        <% end %>
      </.section>

      <%!-- ── Beneficiaries ────────────────────────────────────────────────── --%>
      <.section icon="hero-gift" title={"Beneficiaries (#{@beneficiary_count})"}>
        <div class="space-y-2">
          <div :for={b <- @capsule.beneficiaries} class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100/50 px-4 py-2.5 text-sm">
            <span class="font-medium">{b.name}</span>
            <span :if={b.relationship} class="text-xs text-base-content/50">{b.relationship}</span>
            <span class="ml-auto rounded-full bg-base-200 px-2 py-0.5 text-xs text-base-content/60">{b.status}</span>
            <%= if @capsule.state == :released do %>
              <.button phx-click="claim" phx-value-beneficiary={b.id}>Record claim</.button>
            <% end %>
          </div>
        </div>
        <%= if @capsule.state in [:draft, :sealed] do %>
          <form phx-submit="add_beneficiary" class="mt-3 flex flex-col gap-2 sm:flex-row">
            <input name="name" placeholder="Name" required class="flex-1 rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm" />
            <input name="email" type="email" placeholder="email" required class="flex-1 rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm" />
            <input name="relationship" placeholder="relationship" class="flex-1 rounded-xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm" />
            <.button variant="primary">Add</.button>
          </form>
        <% end %>
      </.section>

      <%!-- ── Lifecycle ────────────────────────────────────────────────────── --%>
      <%= if lifecycle?(@capsule) do %>
        <.section icon="hero-arrow-path" title="Lifecycle">
          {lifecycle_controls(assigns)}
        </.section>
      <% end %>

      <%!-- ── Audit ledger ─────────────────────────────────────────────────── --%>
      <.section icon="hero-finger-print" title="Audit ledger">
        <:aside><.chain_badge status={@chain_status} /></:aside>
        <%= if @audit_events == [] do %>
          <p class="text-sm text-base-content/50">No events recorded yet.</p>
        <% else %>
          <ol class="space-y-2">
            <%= for event <- @audit_events do %>
              <li class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100/50 px-4 py-2.5 text-sm">
                <span class="font-mono text-xs text-base-content/40">#{event.stream_version}</span>
                <span class="font-medium">{humanize_event(event.event_type)}</span>
                <span class="text-base-content/40">{format_clock(event.recorded_at)}</span>
                <span class="ml-auto font-mono text-xs text-base-content/30">
                  {String.slice(event.hash || "", 0, 12)}…
                </span>
              </li>
            <% end %>
          </ol>
        <% end %>
      </.section>
    </Layouts.app>
    """
  end

  # State-driven lifecycle actions. The aggregate is the real guard; these just
  # offer the transitions that make sense from here.
  defp lifecycle_controls(%{capsule: %{state: :sealed}} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.button phx-click="sign_of_life">
        <.icon name="hero-hand-raised" /> Record sign of life
      </.button>
      <.button phx-click="fire_trigger" variant="primary" data-confirm="Fire this capsule's trigger?">
        <.icon name="hero-bolt" /> Fire trigger ({@capsule.access_contract.trigger_type})
      </.button>
    </div>
    """
  end

  defp lifecycle_controls(%{capsule: %{state: :triggered}} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.button phx-click="open_verification" variant="primary">
        <.icon name="hero-magnifying-glass" /> Open verification ({@capsule.access_contract.quorum_threshold}-of-{@capsule.access_contract.quorum_size})
      </.button>
      <.button phx-click="withhold" data-confirm="Withhold this capsule?">Withhold</.button>
    </div>
    """
  end

  defp lifecycle_controls(%{capsule: %{state: :verifying}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <p class="mb-2 text-sm text-base-content/60">
          Attestations: {length(@attestations)} of {@capsule.access_contract.quorum_threshold} needed
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            :for={t <- @capsule.trustees}
            phx-click="attest"
            phx-value-trustee={t.name}
            type="button"
            disabled={t.name in @attestations}
            class={[
              "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm transition",
              if(t.name in @attestations,
                do: "border-emerald-300 bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300",
                else: "border-base-300 bg-base-100 hover:bg-base-200"
              )
            ]}
          >
            <.icon name="hero-check-circle" class="size-4" /> {t.name}
          </button>
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <.button phx-click="record_threshold" variant="primary">
          Record threshold met
        </.button>
        <.button phx-click="release">
          <.icon name="hero-paper-airplane" /> Release
        </.button>
        <.button phx-click="withhold" data-confirm="Withhold this capsule?">Withhold</.button>
      </div>
    </div>
    """
  end

  defp lifecycle_controls(%{capsule: %{state: state}} = assigns) when state in [:released, :withheld, :claimed] do
    ~H"""
    <p class="text-sm text-base-content/60">
      <%= case @capsule.state do %>
        <% :released -> %>
          Released. Record a beneficiary's claim from the Beneficiaries section above.
        <% :withheld -> %>
          Withheld — release was stopped on doubt. This is terminal.
        <% :claimed -> %>
          Claimed by a beneficiary. The capsule has completed its life.
      <% end %>
    </p>
    """
  end

  defp lifecycle_controls(assigns), do: ~H""

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Vault.subscribe_capsules(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Capsule")
     |> assign(:durations, @durations)
     |> assign(:attestations, [])
     |> assign(:capsule_id, id)
     |> load()}
  end

  @impl true
  def handle_event("set_date_contract", %{"seconds" => seconds}, socket) do
    contract_result(
      socket,
      Vault.set_date_contract(scope(socket), socket.assigns.capsule, String.to_integer(seconds))
    )
  end

  def handle_event("set_condition_contract", %{"trigger_type" => trigger, "threshold" => n}, socket) do
    case Map.fetch(@trigger_atoms, trigger) do
      {:ok, trigger_type} ->
        contract_result(
          socket,
          Vault.set_condition_contract(
            scope(socket),
            socket.assigns.capsule,
            trigger_type,
            String.to_integer(n)
          )
        )

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown trigger type.")}
    end
  end

  def handle_event("sealed", params, socket) do
    case Vault.add_sealed_artifact(scope(socket), socket.assigns.capsule, params) do
      {:ok, artifact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sealed “#{artifact.filename}” into the capsule.")
         |> load()
         |> schedule_refresh()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not seal that artifact.")}
    end
  end

  def handle_event("add_trustee", %{"name" => name, "email" => email}, socket) do
    case Vault.add_trustee(scope(socket), socket.assigns.capsule, %{"name" => name, "email" => email}) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Trustee enrolled.") |> load()}

      {:error, :already_a_beneficiary} ->
        {:noreply, put_flash(socket, :error, "That address is already a beneficiary.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not enroll that trustee.")}
    end
  end

  def handle_event("add_beneficiary", %{"name" => name, "email" => email} = params, socket) do
    attrs = %{"name" => name, "email" => email, "relationship" => params["relationship"]}

    case Vault.add_beneficiary(scope(socket), socket.assigns.capsule, attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Beneficiary added.") |> load()}

      {:error, :already_a_trustee} ->
        {:noreply, put_flash(socket, :error, "That address is already a trustee.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add that beneficiary.")}
    end
  end

  def handle_event("seal_capsule", _params, socket) do
    lifecycle_result(socket, Vault.seal_capsule(scope(socket), socket.assigns.capsule), "Capsule sealed.")
  end

  def handle_event("sign_of_life", _params, socket) do
    lifecycle_result(socket, Vault.record_sign_of_life(scope(socket), socket.assigns.capsule), "Sign of life recorded.")
  end

  def handle_event("fire_trigger", _params, socket) do
    trigger = socket.assigns.capsule.access_contract.trigger_type
    lifecycle_result(socket, Vault.fire_trigger(scope(socket), socket.assigns.capsule, trigger), "Trigger fired.")
  end

  def handle_event("open_verification", _params, socket) do
    contract = socket.assigns.capsule.access_contract

    lifecycle_result(
      socket,
      Vault.open_verification(scope(socket), socket.assigns.capsule, contract.quorum_threshold, contract.quorum_size),
      "Verification opened."
    )
  end

  def handle_event("attest", %{"trustee" => name}, socket) do
    {:noreply, assign(socket, :attestations, Enum.uniq([name | socket.assigns.attestations]))}
  end

  def handle_event("record_threshold", _params, socket) do
    lifecycle_result(
      socket,
      Vault.record_threshold_met(scope(socket), socket.assigns.capsule, socket.assigns.attestations),
      "Quorum threshold recorded."
    )
  end

  def handle_event("release", _params, socket) do
    lifecycle_result(socket, Vault.release_capsule(scope(socket), socket.assigns.capsule), "Capsule released.")
  end

  def handle_event("withhold", _params, socket) do
    lifecycle_result(
      socket,
      Vault.withhold_capsule(scope(socket), socket.assigns.capsule, "withheld by owner"),
      "Capsule withheld."
    )
  end

  def handle_event("claim", %{"beneficiary" => beneficiary_id}, socket) do
    lifecycle_result(
      socket,
      Vault.claim_capsule(scope(socket), socket.assigns.capsule, beneficiary_id),
      "Claim recorded."
    )
  end

  # From the TimelockOpen hook after an artifact is opened client-side.
  def handle_event("opened", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  def handle_info({:updated, %Capsule{id: id}}, %{assigns: %{capsule_id: id}} = socket) do
    {:noreply, load(socket)}
  end

  def handle_info({:deleted, %Capsule{id: id}}, %{assigns: %{capsule_id: id}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current capsule was deleted.")
     |> push_navigate(to: ~p"/capsules")}
  end

  def handle_info({type, %Capsule{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  ## Loading / result helpers

  defp scope(socket), do: socket.assigns.current_scope

  defp load(socket) do
    capsule = Vault.get_capsule_with_details!(scope(socket), socket.assigns.capsule_id)

    ciphertexts =
      Map.new(capsule.artifacts, fn artifact ->
        {artifact.id, Vault.read_artifact_ciphertext(artifact) || ""}
      end)

    socket
    |> assign(:capsule, capsule)
    |> assign(:artifact_count, length(capsule.artifacts))
    |> assign(:trustee_count, length(capsule.trustees))
    |> assign(:beneficiary_count, length(capsule.beneficiaries))
    |> assign(:ciphertexts, ciphertexts)
    |> assign(:audit_events, Vault.list_audit_events(capsule.id))
    |> assign(:chain_status, Vault.verify_audit_chain(capsule.id))
  end

  defp contract_result(socket, {:ok, _}),
    do: {:noreply, socket |> put_flash(:info, "Access contract set.") |> load()}

  defp contract_result(socket, {:error, changeset}),
    do: {:noreply, put_flash(socket, :error, "Could not set the contract: #{changeset_error(changeset)}")}

  defp lifecycle_result(socket, :ok, message),
    do: {:noreply, socket |> put_flash(:info, message) |> schedule_refresh() |> load()}

  defp lifecycle_result(socket, {:error, reason}, _message),
    do: {:noreply, put_flash(socket, :error, "Not allowed here: #{inspect(reason)}")}

  # The state projector and audit ledger are eventual — nudge a reload so the UI
  # catches up with the async projections a beat after a dispatch.
  defp schedule_refresh(socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 400)
    socket
  end

  defp changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map(fn {field, [msg | _]} -> "#{field} #{msg}" end)
    |> Enum.join("; ")
  end

  ## Presentation

  defp lifecycle?(%{access_contract: %{trigger_type: :date}}), do: false
  defp lifecycle?(%{access_contract: %{}, state: state}) when state != :draft, do: true
  defp lifecycle?(_), do: false

  defp contract_summary(%{trigger_type: :date, embargo_until: at}),
    do: "Time-locked — unlocks #{format_time(at)}"

  defp contract_summary(%{trigger_type: type}),
    do: "Condition — releases on #{type}, once the trustee quorum attests"

  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :aside
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="mt-8">
      <h2 class="mb-3 flex items-center gap-2 text-sm font-semibold tracking-wide text-base-content/50 uppercase">
        <.icon name={@icon} class="size-4" /> {@title}
        {render_slot(@aside)}
      </h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :state, :atom, required: true

  defp state_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      @state == :draft && "bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300",
      @state == :sealed && "bg-primary/10 text-primary",
      @state in [:triggered, :verifying] && "bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300",
      @state == :released && "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300",
      @state == :withheld && "bg-rose-100 text-rose-700 dark:bg-rose-500/15 dark:text-rose-300",
      @state == :claimed && "bg-base-200 text-base-content/60"
    ]}>
      {@state}
    </span>
    """
  end

  attr :status, :any, required: true

  defp chain_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :ok -> %>
        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-xs font-medium text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300">
          <.icon name="hero-check-badge-micro" class="size-3.5" /> verified intact
        </span>
      <% {:tampered, version} -> %>
        <span class="inline-flex items-center gap-1 rounded-full bg-rose-100 px-2.5 py-0.5 text-xs font-medium text-rose-700 dark:bg-rose-500/15 dark:text-rose-300">
          <.icon name="hero-exclamation-triangle-micro" class="size-3.5" /> tampered at #{version}
        </span>
    <% end %>
    """
  end

  defp humanize_event(type), do: Regex.replace(~r/([a-z])([A-Z])/, type, "\\1 \\2")

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y at %H:%M UTC")
  defp format_time(_), do: "—"

  defp format_clock(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_clock(_), do: ""
end
