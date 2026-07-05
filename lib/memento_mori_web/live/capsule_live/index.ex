defmodule MementoMoriWeb.CapsuleLive.Index do
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Capsules
        <:actions>
          <.button variant="primary" navigate={~p"/capsules/new"}>
            <.icon name="hero-plus" /> New Capsule
          </.button>
        </:actions>
      </.header>

      <.table
        id="capsules"
        rows={@streams.capsules}
        row_click={fn {_id, capsule} -> JS.navigate(~p"/capsules/#{capsule}") end}
      >
        <:col :let={{_id, capsule}} label="Title">{capsule.title}</:col>
        <:col :let={{_id, capsule}} label="Sensitivity tier">{capsule.sensitivity_tier}</:col>
        <:col :let={{_id, capsule}} label="State">{capsule.state}</:col>
        <:action :let={{_id, capsule}}>
          <div class="sr-only">
            <.link navigate={~p"/capsules/#{capsule}"}>Show</.link>
          </div>
          <.link navigate={~p"/capsules/#{capsule}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, capsule}}>
          <.link
            phx-click={JS.push("delete", value: %{id: capsule.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Vault.subscribe_capsules(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Capsules")
     |> stream(:capsules, list_capsules(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    capsule = Vault.get_capsule!(socket.assigns.current_scope, id)
    {:ok, _} = Vault.delete_capsule(socket.assigns.current_scope, capsule)

    {:noreply, stream_delete(socket, :capsules, capsule)}
  end

  @impl true
  def handle_info({type, %MementoMori.Vault.Capsule{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :capsules, list_capsules(socket.assigns.current_scope), reset: true)}
  end

  defp list_capsules(current_scope) do
    Vault.list_capsules(current_scope)
  end
end
