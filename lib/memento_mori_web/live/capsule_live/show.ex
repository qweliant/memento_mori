defmodule MementoMoriWeb.CapsuleLive.Show do
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Capsule {@capsule.id}
        <:subtitle>This is a capsule record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/capsules"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/capsules/#{@capsule}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit capsule
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@capsule.title}</:item>
        <:item title="Sensitivity tier">{@capsule.sensitivity_tier}</:item>
        <:item title="State">{@capsule.state}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Vault.subscribe_capsules(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Capsule")
     |> assign(:capsule, Vault.get_capsule!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %MementoMori.Vault.Capsule{id: id} = capsule},
        %{assigns: %{capsule: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :capsule, capsule)}
  end

  def handle_info(
        {:deleted, %MementoMori.Vault.Capsule{id: id}},
        %{assigns: %{capsule: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current capsule was deleted.")
     |> push_navigate(to: ~p"/capsules")}
  end

  def handle_info({type, %MementoMori.Vault.Capsule{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
