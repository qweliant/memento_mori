defmodule MementoMoriWeb.OwnerSessionController do
  use MementoMoriWeb, :controller

  alias MementoMori.Accounts
  alias MementoMoriWeb.OwnerAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Owner confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"owner" => %{"token" => token} = owner_params}, info) do
    case Accounts.login_owner_by_magic_link(token) do
      {:ok, {owner, tokens_to_disconnect}} ->
        OwnerAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> OwnerAuth.log_in_owner(owner, owner_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/owners/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"owner" => owner_params}, info) do
    %{"email" => email, "password" => password} = owner_params

    if owner = Accounts.get_owner_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> OwnerAuth.log_in_owner(owner, owner_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/owners/log-in")
    end
  end

  def update_password(conn, %{"owner" => owner_params} = params) do
    owner = conn.assigns.current_scope.owner
    true = Accounts.sudo_mode?(owner)
    {:ok, {_owner, expired_tokens}} = Accounts.update_owner_password(owner, owner_params)

    # disconnect all existing LiveViews with old sessions
    OwnerAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:owner_return_to, ~p"/owners/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> OwnerAuth.log_out_owner()
  end
end
