defmodule MementoMoriWeb.OwnerLive.LoginTest do
  use MementoMoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MementoMori.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/owners/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Log in with email"
    end
  end

  describe "owner login - magic link" do
    test "sends magic link email when owner exists", %{conn: conn} do
      owner = owner_fixture()

      {:ok, lv, _html} = live(conn, ~p"/owners/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", owner: %{email: owner.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~ "If your email is in our system"

      assert MementoMori.Repo.get_by!(MementoMori.Accounts.OwnerToken, owner_id: owner.id).context ==
               "login"
    end

    test "does not disclose if owner is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", owner: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/owners/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "owner login - password" do
    test "redirects if owner logs in with valid credentials", %{conn: conn} do
      owner = owner_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/owners/log-in")

      form =
        form(lv, "#login_form_password",
          owner: %{email: owner.email, password: valid_owner_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/owners/log-in")

      form =
        form(lv, "#login_form_password", owner: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/owners/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/owners/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/owners/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      owner = owner_fixture()
      %{owner: owner, conn: log_in_owner(conn, owner)}
    end

    test "shows login page with email filled in", %{conn: conn, owner: owner} do
      {:ok, _lv, html} = live(conn, ~p"/owners/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="owner[email]" id="login_form_magic_email" value="#{owner.email}")
    end
  end
end
