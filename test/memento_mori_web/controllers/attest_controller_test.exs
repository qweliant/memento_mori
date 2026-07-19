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

  test "records a signed attestation on submit", %{conn: conn, trustee: trustee} do
    token = CapabilityToken.sign_trustee(trustee)
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    attested_at = "2026-07-18T12:00:00Z"
    message = "#{trustee.capsule_id}|#{trustee.id}|#{attested_at}"

    signature =
      :crypto.sign(:ecdsa, :sha256, message, [private, :secp256r1])
      |> MementoMori.Vault.Signature.der_to_raw()

    conn =
      post(conn, ~p"/attest/#{token}", %{
        "note" => "seen",
        "public_key" => Base.encode64(public),
        "signature" => Base.encode64(signature),
        "attested_at" => attested_at
      })

    assert html_response(conn, 200) =~ "confirmation has been recorded"
    assert Vault.attested_trustee_names(trustee.capsule_id) == ["Ada"]
  end

  test "rejects an unsigned submit (fail closed)", %{conn: conn, trustee: trustee} do
    token = CapabilityToken.sign_trustee(trustee)
    conn = post(conn, ~p"/attest/#{token}", %{"note" => "seen"})
    assert html_response(conn, 422) =~ "couldn't confirm your signature"
    assert Vault.attested_trustee_names(trustee.capsule_id) == []
  end

  test "rejects a signature from the wrong key", %{conn: conn, trustee: trustee} do
    token = CapabilityToken.sign_trustee(trustee)
    {public, _} = :crypto.generate_key(:ecdh, :secp256r1)
    {_, wrong_private} = :crypto.generate_key(:ecdh, :secp256r1)
    attested_at = "2026-07-18T12:00:00Z"
    message = "#{trustee.capsule_id}|#{trustee.id}|#{attested_at}"

    signature =
      :crypto.sign(:ecdsa, :sha256, message, [wrong_private, :secp256r1])
      |> MementoMori.Vault.Signature.der_to_raw()

    conn =
      post(conn, ~p"/attest/#{token}", %{
        "public_key" => Base.encode64(public),
        "signature" => Base.encode64(signature),
        "attested_at" => attested_at
      })

    assert html_response(conn, 422) =~ "couldn't confirm your signature"
    assert Vault.attested_trustee_names(trustee.capsule_id) == []
  end

  test "rejects an invalid token", %{conn: conn} do
    conn = get(conn, ~p"/attest/bogus")
    assert html_response(conn, 404) =~ "isn't valid"
  end
end
