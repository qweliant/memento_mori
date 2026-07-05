defmodule MementoMoriWeb.CapsuleLive.Form do
  use MementoMoriWeb, :live_view

  alias MementoMori.Vault
  alias MementoMori.Vault.Capsule

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage capsule records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="capsule-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input
          field={@form[:sensitivity_tier]}
          type="select"
          label="Sensitivity tier"
          options={Enum.map(Capsule.sensitivity_tiers(), &{Phoenix.Naming.humanize(&1), &1})}
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Capsule</.button>
          <.button navigate={return_path(@current_scope, @return_to, @capsule)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    capsule = Vault.get_capsule!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Capsule")
    |> assign(:capsule, capsule)
    |> assign(:form, to_form(Vault.change_capsule(socket.assigns.current_scope, capsule)))
  end

  defp apply_action(socket, :new, _params) do
    capsule = %Capsule{owner_id: socket.assigns.current_scope.owner.id}

    socket
    |> assign(:page_title, "New Capsule")
    |> assign(:capsule, capsule)
    |> assign(:form, to_form(Vault.change_capsule(socket.assigns.current_scope, capsule)))
  end

  @impl true
  def handle_event("validate", %{"capsule" => capsule_params}, socket) do
    changeset =
      Vault.change_capsule(socket.assigns.current_scope, socket.assigns.capsule, capsule_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"capsule" => capsule_params}, socket) do
    save_capsule(socket, socket.assigns.live_action, capsule_params)
  end

  defp save_capsule(socket, :edit, capsule_params) do
    case Vault.update_capsule(
           socket.assigns.current_scope,
           socket.assigns.capsule,
           capsule_params
         ) do
      {:ok, capsule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Capsule updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, capsule)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_capsule(socket, :new, capsule_params) do
    case Vault.create_capsule(socket.assigns.current_scope, capsule_params) do
      {:ok, capsule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Capsule created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, capsule)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _capsule), do: ~p"/capsules"
  defp return_path(_scope, "show", capsule), do: ~p"/capsules/#{capsule}"
end
