defmodule MementoMoriWeb.OwnerLive.RegistrationTest do
  use MementoMoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MementoMori.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/owners/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_owner(owner_fixture())
        |> live(~p"/owners/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(owner: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register owner" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/register")

      email = unique_owner_email()
      form = form(lv, "#registration_form", owner: valid_owner_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/register")

      owner = owner_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          owner: %{"email" => owner.email}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert login_html =~ "Log in"
    end
  end
end
