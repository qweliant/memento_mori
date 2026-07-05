defmodule MementoMoriWeb.OwnerSessionControllerTest do
  use MementoMoriWeb.ConnCase, async: true

  import MementoMori.AccountsFixtures
  alias MementoMori.Accounts

  setup do
    %{unconfirmed_owner: unconfirmed_owner_fixture(), owner: owner_fixture()}
  end

  describe "POST /owners/log-in - email and password" do
    test "logs the owner in", %{conn: conn, owner: owner} do
      owner = set_password(owner)

      conn =
        post(conn, ~p"/owners/log-in", %{
          "owner" => %{"email" => owner.email, "password" => valid_owner_password()}
        })

      assert get_session(conn, :owner_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ owner.email
      assert response =~ ~p"/owners/settings"
      assert response =~ ~p"/owners/log-out"
    end

    test "logs the owner in with remember me", %{conn: conn, owner: owner} do
      owner = set_password(owner)

      conn =
        post(conn, ~p"/owners/log-in", %{
          "owner" => %{
            "email" => owner.email,
            "password" => valid_owner_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_memento_mori_web_owner_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the owner in with return to", %{conn: conn, owner: owner} do
      owner = set_password(owner)

      conn =
        conn
        |> init_test_session(owner_return_to: "/foo/bar")
        |> post(~p"/owners/log-in", %{
          "owner" => %{
            "email" => owner.email,
            "password" => valid_owner_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, owner: owner} do
      conn =
        post(conn, ~p"/owners/log-in?mode=password", %{
          "owner" => %{"email" => owner.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/owners/log-in"
    end
  end

  describe "POST /owners/log-in - magic link" do
    test "logs the owner in", %{conn: conn, owner: owner} do
      {token, _hashed_token} = generate_owner_magic_link_token(owner)

      conn =
        post(conn, ~p"/owners/log-in", %{
          "owner" => %{"token" => token}
        })

      assert get_session(conn, :owner_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ owner.email
      assert response =~ ~p"/owners/settings"
      assert response =~ ~p"/owners/log-out"
    end

    test "confirms unconfirmed owner", %{conn: conn, unconfirmed_owner: owner} do
      {token, _hashed_token} = generate_owner_magic_link_token(owner)
      refute owner.confirmed_at

      conn =
        post(conn, ~p"/owners/log-in", %{
          "owner" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :owner_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Owner confirmed successfully."

      assert Accounts.get_owner!(owner.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ owner.email
      assert response =~ ~p"/owners/settings"
      assert response =~ ~p"/owners/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/owners/log-in", %{
          "owner" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/owners/log-in"
    end
  end

  describe "DELETE /owners/log-out" do
    test "logs the owner out", %{conn: conn, owner: owner} do
      conn = conn |> log_in_owner(owner) |> delete(~p"/owners/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :owner_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the owner is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/owners/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :owner_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
