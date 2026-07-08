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
  alias MementoMoriWeb.CapabilityToken

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
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:capsules}>
      <%!-- Header --%>
      <div class="flex items-center justify-between gap-5 mb-6">
        <div class="flex items-center gap-3.5">
          <.link navigate={~p"/capsules"} class="btn btn-ghost btn-square btn-sm">
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <div>
            <h1 class="mm-serif text-2xl font-medium">{@capsule.title}</h1>
            <p class="text-sm text-base-content/60 mt-1">
              {Phoenix.Naming.humanize(@capsule.sensitivity_tier)} sensitivity · opened {format_clock_date(@capsule.inserted_at)}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.link navigate={~p"/capsules/#{@capsule}/edit?return_to=show"} class="btn btn-ghost btn-sm">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.link>
          <.link
            phx-click="delete"
            data-confirm="Delete this capsule? This cannot be undone."
            class="btn btn-ghost btn-sm text-error"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </.link>
          <.state_badge state={@capsule.state} />
        </div>
      </div>

      <.lifecycle_stepper state={@capsule.state} />

      <%!-- ── Contract set: the rich detail (mirrors the mock) ───────────────── --%>
      <%= if @capsule.access_contract do %>
        <div class="grid grid-cols-1 lg:grid-cols-[1.25fr_1fr] gap-4 mb-4">
          <%!-- Left: verification (condition) or timelock (date) --%>
          <%= if @capsule.access_contract.trigger_type == :date do %>
            <section class="mm-panel">
              <div class="mm-section-label">Timelock — drand</div>
              <div class="flex items-center gap-4 mb-3.5">
                <div class="flex items-center justify-center size-13 rounded-2xl bg-primary/15 text-primary">
                  <.icon name="hero-lock-closed" class="size-6" />
                </div>
                <div>
                  <div class="mm-serif text-xl font-medium">
                    Unlocks {format_time(@capsule.access_contract.embargo_until)}
                  </div>
                  <div class="text-sm text-base-content/60 mt-0.5">
                    drand round {@capsule.access_contract.timelock_round}
                  </div>
                </div>
              </div>
              <p class="mm-principle">
                The content key is timelock-encrypted to a future drand round. No quorum,
                no operator trust — the network refuses the key until the round is emitted.
              </p>
            </section>
          <% else %>
            <section class="mm-panel">
              <div class="mm-section-label">Verification — trustee quorum</div>
              <span class="mm-verify-badge">
                {attested_count(@capsule)} of {@capsule.access_contract.quorum_threshold} attested ·
                quorum {@capsule.access_contract.quorum_threshold}-of-{@capsule.access_contract.quorum_size}
              </span>
              <div class="mm-progress">
                <i style={"width: #{quorum_pct(@capsule)}%"}></i>
              </div>
              <div :for={t <- @capsule.trustees} class="mm-party-row">
                <div>
                  <div class="mm-party-name">{t.name}</div>
                  <div class="mm-party-role">weight ×{t.weight}</div>
                </div>
                <div class="ml-auto flex items-center gap-2.5">
                  <a href={@trustee_links[t.id]} target="_blank" class="btn btn-ghost btn-xs">
                    <.icon name="hero-link" class="size-3.5" /> Invite
                  </a>
                  <.status_pill status={t.status} />
                </div>
              </div>
              <p class="mm-principle">
                Correctness over availability — a false release is irreversible, so release
                is only reachable once the quorum attests. Doubt withholds.
              </p>
            </section>
          <% end %>

          <%!-- Right: access contract + owner presence --%>
          <section class="mm-panel">
            <div class="mm-section-label">Access contract</div>
            <div class="mm-kv">
              <span>Trigger</span><b>{Phoenix.Naming.humanize(@capsule.access_contract.trigger_type)}</b>
            </div>
            <div class="mm-kv">
              <span>Release path</span>
              <b>{if @capsule.access_contract.trigger_type == :date, do: "drand timelock — trustless", else: "Trustee quorum attestation"}</b>
            </div>
            <div class="mm-kv">
              <span>Cooling-off</span>
              <b>{if @capsule.access_contract.cooling_off_days > 0, do: "#{@capsule.access_contract.cooling_off_days} days", else: "None"}</b>
            </div>
            <div class="mm-kv">
              <span>Delivery</span><b>{Phoenix.Naming.humanize(@capsule.access_contract.delivery_pacing)}</b>
            </div>

            <div class="mm-section-label mt-6">Owner presence</div>
            <div class="flex items-baseline justify-between gap-2.5">
              <span class="text-sm text-base-content/60">Last sign of life</span>
              <span class="mm-serif text-xl font-medium">{last_sign_of_life(@audit_events)}</span>
            </div>
            <p :if={@capsule.state not in [:sealed, :draft]} class="text-sm text-base-content/50 mt-2">
              Sign-of-life closes once a trigger fires — this record is now historical.
            </p>
          </section>
        </div>

        <%!-- Seal box: draft + date contract → seal artifacts to the timelock round --%>
        <div
          :if={@capsule.state == :draft and @capsule.access_contract.timelock_round}
          class="mm-panel mb-4"
        >
          <div class="mm-section-label">Seal an artifact</div>
          <div
            id="capsule-seal"
            phx-hook="CapsuleSeal"
            phx-update="ignore"
            data-round={@capsule.access_contract.timelock_round}
          >
            <input data-seal-filename type="text" placeholder="letter.txt" class="input w-full mb-3" />
            <textarea
              data-seal-note
              rows="3"
              placeholder="Write the message to seal to the future…"
              class="textarea w-full resize-y mb-3"
            ></textarea>
            <div class="flex items-center gap-3">
              <button data-seal-submit type="button" class="btn btn-primary btn-sm">
                <.icon name="hero-lock-closed" class="size-4" /> Seal to the future
              </button>
              <p data-seal-status class="text-sm text-base-content/60"></p>
            </div>
          </div>
        </div>
      <% else %>
        <%!-- Draft, no contract yet: choose how this capsule wakes --%>
        <div class="mm-panel mb-4">
          <div class="mm-section-label">Unlock — choose how this capsule wakes</div>
          <%= if @capsule.state == :draft do %>
            <div class="grid gap-4 sm:grid-cols-2">
              <form phx-submit="set_date_contract" class="mm-artifact">
                <p class="mb-1 font-medium">A specific time</p>
                <p class="mb-3 text-sm text-base-content/60">Cryptographically enforced by drand — trustless.</p>
                <select name="seconds" class="select w-full mb-3">
                  <%= for {label, seconds} <- @durations do %>
                    <option value={seconds} selected={seconds == 120}>{label}</option>
                  <% end %>
                </select>
                <.button variant="primary">Time-lock it</.button>
              </form>

              <form phx-submit="set_condition_contract" class="mm-artifact">
                <p class="mb-1 font-medium">A condition</p>
                <p class="mb-3 text-sm text-base-content/60">
                  Released after trustees attest ({@trustee_count} enrolled).
                </p>
                <div class="mb-3 flex gap-2">
                  <select name="trigger_type" class="select flex-1">
                    <option value="death">After I'm gone</option>
                    <option value="life_event">A life event</option>
                    <option value="inactivity">Inactivity</option>
                  </select>
                  <input name="threshold" type="number" min="1" value="1" class="input w-24" />
                </div>
                <.button variant="primary">Set quorum</.button>
                <p :if={@trustee_count == 0} class="mt-2 text-xs text-warning">
                  Enroll trustees below first.
                </p>
              </form>
            </div>
          <% else %>
            <p class="text-sm text-base-content/50">No access contract was set before sealing.</p>
          <% end %>
        </div>
      <% end %>

      <%!-- ── Trustees (enrollment / review during setup) ──────────────────── --%>
      <section :if={@capsule.state in [:draft, :sealed]} class="mm-panel mb-4">
        <div class="mm-section-label">
          Trustees <span class="text-base-content/40 normal-case tracking-normal">· they attest · {@trustee_count}</span>
        </div>
        <div :for={t <- @capsule.trustees} class="mm-party-row">
          <div>
            <div class="mm-party-name">{t.name}</div>
            <div class="mm-party-role">weight ×{t.weight}</div>
          </div>
          <div class="ml-auto flex items-center gap-2.5">
            <a href={@trustee_links[t.id]} target="_blank" class="btn btn-ghost btn-xs">
              <.icon name="hero-link" class="size-3.5" /> Invite
            </a>
            <.status_pill status={t.status} />
          </div>
        </div>
        <form phx-submit="add_trustee" class="flex flex-col gap-2 sm:flex-row mt-3">
          <input name="name" placeholder="Name" required class="input flex-1" />
          <input name="email" type="email" placeholder="email" required class="input flex-1" />
          <.button variant="primary">Add trustee</.button>
        </form>
      </section>

      <%!-- Beneficiaries --%>
      <section class="mm-panel mb-4">
        <div class="mm-section-label">
          Beneficiaries <span class="text-base-content/40 normal-case tracking-normal">· they receive · {@beneficiary_count}</span>
        </div>
        <div :for={b <- @capsule.beneficiaries} class="mm-party-row">
          <div>
            <div class="mm-party-name">{b.name}</div>
            <div class="mm-party-role">{b.relationship}</div>
          </div>
          <div class="ml-auto flex items-center gap-2.5">
            <.status_pill status={b.status} />
            <a
              :if={@capsule.state == :released}
              href={@beneficiary_links[b.id]}
              target="_blank"
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-link" class="size-3.5" /> Claim link
            </a>
            <.button :if={@capsule.state == :released} phx-click="claim" phx-value-beneficiary={b.id}>
              Record claim
            </.button>
          </div>
        </div>
        <p class="mm-principle">
          A trustee attests; a beneficiary receives — and the two can never be the same
          person. That wall stops an heir from both faking the trigger and collecting the archive.
        </p>
        <form :if={@capsule.state in [:draft, :sealed]} phx-submit="add_beneficiary" class="flex flex-col gap-2 sm:flex-row mt-3">
          <input name="name" placeholder="Name" required class="input flex-1" />
          <input name="email" type="email" placeholder="email" required class="input flex-1" />
          <input name="relationship" placeholder="relationship" class="input flex-1" />
          <.button variant="primary">Add</.button>
        </form>
      </section>

      <%!-- Artifacts --%>
      <section class="mm-panel mb-4">
        <div class="mm-section-label">
          Artifacts <span class="text-base-content/40 normal-case tracking-normal">· {@artifact_count}</span>
        </div>
        <p :if={@artifact_count == 0} class="text-sm text-base-content/50">Nothing sealed into this capsule yet.</p>
        <div :for={artifact <- @capsule.artifacts} class="mm-artifact mb-3">
          <div class="flex items-baseline justify-between gap-3">
            <span class="font-medium">{artifact.filename}</span>
            <span class="mm-hash">{artifact.byte_size} bytes</span>
          </div>
          <div class="flex flex-wrap gap-1.5 items-center mt-2">
            <span class="mm-chip">sha256 {String.slice(artifact.fixity_digest || "", 0, 16)}…</span>
            <span :if={artifact.provenance_manifest} class="mm-chip mm-chip-prov">C2PA provenance</span>
          </div>
          <pre id={"ct-#{artifact.id}"} class="hidden">{Map.get(@ciphertexts, artifact.id, "")}</pre>
          <div class="mt-3">
            <button
              id={"open-#{artifact.id}"}
              phx-hook="TimelockOpen"
              data-id={artifact.id}
              data-ciphertext-id={"ct-#{artifact.id}"}
              data-target={"#reveal-#{artifact.id}"}
              type="button"
              class="btn btn-sm"
            >
              <.icon name="hero-key" class="size-4" /> Try to open
            </button>
          </div>
          <div id={"reveal-#{artifact.id}"} class="mm-envelope hidden whitespace-pre-wrap"></div>
        </div>
        <div :if={@capsule.state == :draft and @artifact_count > 0} class="mt-4">
          <.button
            phx-click="seal_capsule"
            variant="primary"
            data-confirm="Seal this capsule? Its artifacts freeze under the access contract."
          >
            <.icon name="hero-lock-closed" class="size-4" /> Seal capsule
          </.button>
        </div>
        <p class="flex items-center gap-1.5 text-xs text-base-content/45 mt-3">
          <.icon name="hero-lock-closed" class="size-3.5" />
          Encrypted client-side before upload — the operator only ever holds ciphertext.
        </p>
      </section>

      <%!-- Lifecycle controls (unchanged) --%>
      <section :if={lifecycle?(@capsule)} class="mm-panel mb-4">
        <div class="mm-section-label">Lifecycle</div>
        {lifecycle_controls(assigns)}
      </section>

      <%!-- Audit ledger --%>
      <section class="mm-panel">
        <div class="mm-section-label">
          Audit ledger <span class="text-base-content/40 normal-case tracking-normal">· hash-chained</span>
          <span class="ml-auto"><.chain_badge status={@chain_status} /></span>
        </div>
        <p :if={@audit_events == []} class="text-sm text-base-content/50">No events recorded yet.</p>
        <div :for={event <- @audit_events} class="mm-ledger-row">
          <span class="mm-ledger-ver">#{event.stream_version}</span>
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline justify-between gap-2.5">
              <span class="mm-ledger-event">{humanize_event(event.event_type)}</span>
              <span class="mm-hash">{String.slice(event.hash || "", 0, 12)}…</span>
            </div>
            <div class="mm-ledger-actor">{format_clock(event.recorded_at)}</div>
          </div>
        </div>
      </section>
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
      <p class="text-sm text-base-content/60">
        {length(@attestations)} of {@capsule.access_contract.quorum_threshold} trustees have attested
        at their capability links. Share each trustee's invite link above; once the quorum is in,
        record the threshold and release.
      </p>
      <div class="flex flex-wrap gap-2">
        <.button phx-click="record_threshold" variant="primary">Record threshold met</.button>
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

  def handle_event("delete", _params, socket) do
    {:ok, _} = Vault.delete_capsule(scope(socket), socket.assigns.capsule)

    {:noreply,
     socket
     |> put_flash(:info, "Capsule deleted.")
     |> push_navigate(to: ~p"/capsules")}
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
    |> assign(:attestations, Vault.attested_trustee_names(capsule.id))
    |> assign(:trustee_links, trustee_links(capsule.trustees))
    |> assign(:beneficiary_links, beneficiary_links(capsule.beneficiaries))
    |> assign(:ciphertexts, ciphertexts)
    |> assign(:audit_events, Vault.list_audit_events(capsule.id))
    |> assign(:chain_status, Vault.verify_audit_chain(capsule.id))
  end

  # Full shareable capability URLs per party — the signed link is the authorization.
  defp trustee_links(trustees) do
    Map.new(trustees, fn t -> {t.id, url(~p"/attest/#{CapabilityToken.sign_trustee(t)}")} end)
  end

  defp beneficiary_links(beneficiaries) do
    Map.new(beneficiaries, fn b -> {b.id, url(~p"/claim/#{CapabilityToken.sign_beneficiary(b)}")} end)
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

  attr :status, :any, required: true

  defp chain_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :ok -> %>
        <span class="inline-flex items-center gap-1 rounded-full bg-success/15 px-2.5 py-0.5 text-xs font-medium text-success">
          <.icon name="hero-check-badge-micro" class="size-3.5" /> verified intact
        </span>
      <% {:tampered, version} -> %>
        <span class="inline-flex items-center gap-1 rounded-full bg-error/15 px-2.5 py-0.5 text-xs font-medium text-error">
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

  defp attested_count(%{trustees: trustees}) when is_list(trustees),
    do: Enum.count(trustees, &(&1.status == :confirmed))

  defp attested_count(_), do: 0

  defp quorum_pct(%{access_contract: %{quorum_threshold: n}} = capsule) when is_integer(n) and n > 0,
    do: min(100, round(attested_count(capsule) / n * 100))

  defp quorum_pct(_), do: 0

  # Newest SignOfLifeRecorded from the audit stream, or a fallback string.
  defp last_sign_of_life(events) do
    events
    |> Enum.filter(&(&1.event_type == "SignOfLifeRecorded"))
    |> Enum.map(& &1.recorded_at)
    |> Enum.max(DateTime, fn -> nil end)
    |> case do
      nil -> "Not yet active"
      dt -> format_time(dt)
    end
  end

  defp format_clock_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_clock_date(_), do: "—"
end
