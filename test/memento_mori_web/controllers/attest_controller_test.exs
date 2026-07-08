defmodule MementoMoriWeb.AttestControllerTest do
  use MementoMoriWeb.ConnCase

  import MementoMori.AccountsFixtures
  import MementoMori.VaultFixtures

  alias MementoMori.Vault
  alias MementoMoriWeb.CapabilityToken

  setup do
    scope = owner_scope_fixture()
    capsule = capsule_fixture(scope)
    {:ok, trustee} = Vault.add_trustee(scope, capsule, %{"name" => "Ada", "email" => "ada@example.com"})
    %{trustee: trustee}
  end

  test "shows the attestation page for a valid token", %{conn: conn, trustee: trustee} do
    token = CapabilityToken.sign_trustee(trustee)
    conn = get(conn, ~p"/attest/#{token}")
    assert html_response(conn, 200) =~ "asked to confirm"
  end

  test "records an attestation on submit", %{conn: conn, trustee: trustee} do
    token = CapabilityToken.sign_trustee(trustee)
    conn = post(conn, ~p"/attest/#{token}", %{"note" => "seen"})
    assert html_response(conn, 200) =~ "confirmation has been recorded"
    assert Vault.attested_trustee_names(trustee.capsule_id) == ["Ada"]
  end

  test "rejects an invalid token", %{conn: conn} do
    conn = get(conn, ~p"/attest/bogus")
    assert html_response(conn, 404) =~ "isn't valid"
  end
end
