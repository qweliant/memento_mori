defmodule MementoMoriWeb.CapsuleLive.Index do
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:capsules}>
      <div class="flex items-start justify-between gap-6 mb-8">
        <div>
          <h1 class="mm-serif text-3xl font-medium">Capsules</h1>
          <p class="text-sm text-base-content/60 mt-2">
            A quiet record of what you're keeping, and for whom.
          </p>
        </div>
        <.button variant="primary" navigate={~p"/capsules/new"}>
          <.icon name="hero-plus" class="size-4" /> New Capsule
        </.button>
      </div>

      <div id="capsules" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.link
          :for={{id, capsule} <- @streams.capsules}
          id={id}
          navigate={~p"/capsules/#{capsule}"}
          class="mm-card block no-underline"
        >
          <div class="flex items-start justify-between gap-3 mb-3">
            <div class="mm-card-title">{capsule.title}</div>
            <div class="flex gap-1.5 shrink-0">
              <.tier_badge tier={capsule.sensitivity_tier} />
              <.state_badge state={capsule.state} />
            </div>
          </div>
          <div class="flex items-center gap-2 text-sm">
            <.icon name="hero-lock-closed" class="size-3.5 text-base-content/40" />
            <span>{contract_line(capsule)}</span>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end

  # Card summary line. Safe whether or not the access_contract is preloaded.
  defp contract_line(%{access_contract: %Ecto.Association.NotLoaded{}}), do: "—"
  defp contract_line(%{access_contract: nil}), do: "No unlock set"

  defp contract_line(%{access_contract: %{trigger_type: :date} = ac}) do
    "Time-locked · drand round #{ac.timelock_round}"
  end

  defp contract_line(%{access_contract: %{trigger_type: t} = ac}) do
    quorum =
      if ac.quorum_threshold, do: " · #{ac.quorum_threshold}-of-#{ac.quorum_size} quorum", else: ""

    "#{Phoenix.Naming.humanize(t)}#{quorum}"
  end

  defp contract_line(_), do: "No unlock set"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Vault.subscribe_capsules(scope)
      # First visit: land the owner on a few starter drafts instead of a blank page.
      Vault.ensure_starter_capsules(scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Capsules")
     |> stream(:capsules, list_capsules(scope))}
  end

  @impl true
  def handle_info({type, %MementoMori.Vault.Capsule{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :capsules, list_capsules(socket.assigns.current_scope), reset: true)}
  end

  defp list_capsules(current_scope) do
    current_scope
    |> Vault.list_capsules()
    |> MementoMori.Repo.preload(:access_contract)
  end
end
