defmodule MementoMoriWeb.ClaimLiveTest do
  use MementoMoriWeb.ConnCase

  import Phoenix.LiveViewTest
  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Vault
  alias MementoMoriWeb.CapabilityToken

  test "an invalid token shows an invalid message", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/claim/bogus")
    assert html =~ "invalid or has expired"
  end

  test "a valid token shows the claim page", %{conn: conn} do
    scope = owner_scope_fixture()
    capsule = capsule_fixture(scope)
    {:ok, beneficiary} = Vault.add_beneficiary(scope, capsule, %{"name" => "Bo", "email" => "bo@example.com"})

    token = CapabilityToken.sign_beneficiary(beneficiary)
    {:ok, _live, html} = live(conn, ~p"/claim/#{token}")
    assert html =~ "Something was left for you"
    # a draft capsule isn't released, so nothing is available yet
    assert html =~ "when the time comes"
  end
end
