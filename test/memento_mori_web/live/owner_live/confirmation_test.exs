defmodule MementoMoriWeb.OwnerLive.ConfirmationTest do
  use MementoMoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MementoMori.AccountsFixtures

  alias MementoMori.Accounts

  setup do
    %{unconfirmed_owner: unconfirmed_owner_fixture(), confirmed_owner: owner_fixture()}
  end

  describe "Confirm owner" do
    test "renders confirmation page for unconfirmed owner", %{
      conn: conn,
      unconfirmed_owner: owner
    } do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/owners/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
    end

    test "renders login page for confirmed owner", %{conn: conn, confirmed_owner: owner} do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/owners/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Keep me logged in on this device"
    end

    test "renders login page for already logged in owner", %{conn: conn, confirmed_owner: owner} do
      conn = log_in_owner(conn, owner)

      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/owners/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Log in"
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_owner: owner} do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/owners/log-in/#{token}")

      form = form(lv, "#confirmation_form", %{"owner" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Owner confirmed successfully"

      assert Accounts.get_owner!(owner.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :owner_token)
      assert redirected_to(conn) == ~p"/"

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/owners/log-in/#{token}")
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "logs confirmed owner in without changing confirmed_at", %{
      conn: conn,
      confirmed_owner: owner
    } do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/owners/log-in/#{token}")

      form = form(lv, "#login_form", %{"owner" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Welcome back!"

      assert Accounts.get_owner!(owner.id).confirmed_at == owner.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/owners/log-in/#{token}")
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/owners/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end
  end
end
