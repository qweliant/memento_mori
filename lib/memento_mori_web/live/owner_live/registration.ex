defmodule MementoMoriWeb.OwnerLive.Registration do
  use MementoMoriWeb, :live_view

  alias MementoMori.Accounts
  alias MementoMori.Accounts.Owner

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/owners/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{owner: owner}}} = socket)
      when not is_nil(owner) do
    {:ok, redirect(socket, to: MementoMoriWeb.OwnerAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_owner_email(%Owner{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"owner" => owner_params}, socket) do
    case Accounts.register_owner(owner_params) do
      {:ok, owner} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            owner,
            &url(~p"/owners/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{owner.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/owners/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"owner" => owner_params}, socket) do
    changeset = Accounts.change_owner_email(%Owner{}, owner_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "owner")
    assign(socket, form: form)
  end
end
