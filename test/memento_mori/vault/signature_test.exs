defmodule MementoMori.Vault.SignatureTest do
  @moduledoc """
  ECDSA P-256 verification of trustee attestation signatures. The browser signs
  with WebCrypto (raw public point, P1363 signature); here we stand in for it
  with `:crypto`, converting its DER signatures to the raw form the client sends.
  """
  use ExUnit.Case, async: true

  alias MementoMori.Vault.Signature

  setup do
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    %{public: public, private: private}
  end

  # Mimic the browser: raw uncompressed public point + raw r||s signature.
  defp raw_sign(private, message) do
    :crypto.sign(:ecdsa, :sha256, message, [private, :secp256r1]) |> Signature.der_to_raw()
  end

  test "accepts a signature made by the matching key", %{public: public, private: private} do
    message = "capsule|trustee|2026-07-18T12:00:00Z"
    assert Signature.valid?(public, message, raw_sign(private, message))
  end

  test "rejects a signature over a different message", %{public: public, private: private} do
    signature = raw_sign(private, "capsule|trustee|2026-07-18T12:00:00Z")
    refute Signature.valid?(public, "capsule|trustee|2026-07-18T13:00:00Z", signature)
  end

  test "rejects a signature from a different key", %{public: public} do
    {_other_public, other_private} = :crypto.generate_key(:ecdh, :secp256r1)
    message = "capsule|trustee|now"
    refute Signature.valid?(public, message, raw_sign(other_private, message))
  end

  test "rejects a malformed signature", %{public: public} do
    refute Signature.valid?(public, "m", <<0>>)
    refute Signature.valid?(public, "m", :crypto.strong_rand_bytes(64))
  end

  test "der_to_raw then raw_to_der preserves the signature", %{public: public, private: private} do
    der = :crypto.sign(:ecdsa, :sha256, "payload", [private, :secp256r1])
    raw = Signature.der_to_raw(der)
    assert byte_size(raw) == 64
    # A round-trip through raw form must still verify — proving r and s survived.
    assert Signature.valid?(public, "payload", raw)
  end
end
