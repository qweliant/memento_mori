defmodule MementoMori.Vault.Signature do
  @moduledoc """
  Verification of trustee attestation signatures — ECDSA over NIST P-256
  (secp256r1) with SHA-256, matching what the browser's WebCrypto produces.

  The browser emits the public key as a raw uncompressed point (65 bytes,
  `0x04 || X || Y`, from `exportKey("raw")`) and the signature in the raw
  IEEE-P1363 form (`r || s`, 32 bytes each). Erlang's `:crypto.verify/5` expects
  a DER-encoded `ECDSA-Sig-Value` instead, so we transcode P1363 → DER before
  verifying. No external dependencies — just `:crypto` and hand-rolled DER.
  """

  @curve :secp256r1

  @doc """
  True if `raw_signature` (P1363 `r||s`, 64 bytes) is a valid signature of
  `message` under the public point `public_point` (65-byte uncompressed). Any
  malformed input returns false rather than raising.
  """
  @spec valid?(binary(), binary(), binary()) :: boolean()
  def valid?(public_point, message, raw_signature)
      when is_binary(public_point) and is_binary(message) and byte_size(raw_signature) == 64 do
    der = raw_to_der(raw_signature)
    :crypto.verify(:ecdsa, :sha256, message, der, [public_point, @curve])
  rescue
    _ -> false
  end

  def valid?(_public_point, _message, _raw_signature), do: false

  @doc "Transcode a raw P1363 ECDSA signature (`r||s`) to a DER `SEQUENCE{INTEGER r, INTEGER s}`."
  @spec raw_to_der(binary()) :: binary()
  def raw_to_der(<<r::binary-size(32), s::binary-size(32)>>) do
    body = der_integer(r) <> der_integer(s)
    # r and s each encode to <= 33 bytes, so the sequence body stays < 128 and a
    # single-byte length is always sufficient.
    <<0x30, byte_size(body)::8>> <> body
  end

  @doc "Inverse of `raw_to_der/1` — DER `ECDSA-Sig-Value` back to raw `r||s`. Used by tests to mimic the browser."
  @spec der_to_raw(binary()) :: binary()
  def der_to_raw(<<0x30, _len::8, rest::binary>>) do
    {r, rest1} = take_integer(rest)
    {s, _rest2} = take_integer(rest1)
    pad32(r) <> pad32(s)
  end

  defp der_integer(bin) do
    trimmed = trim_leading_zeros(bin)
    # A leading high bit would read as a negative integer; prefix 0x00 to keep it positive.
    padded = if high_bit?(trimmed), do: <<0>> <> trimmed, else: trimmed
    <<0x02, byte_size(padded)::8>> <> padded
  end

  defp take_integer(<<0x02, len::8, rest::binary>>) do
    <<int::binary-size(^len), tail::binary>> = rest
    {trim_leading_zeros(int), tail}
  end

  defp trim_leading_zeros(<<0, rest::binary>>) when byte_size(rest) > 0, do: trim_leading_zeros(rest)
  defp trim_leading_zeros(bin), do: bin

  defp high_bit?(<<b, _::binary>>), do: b >= 0x80
  defp high_bit?(_), do: false

  # Left-pad (or trim) to a fixed 32-byte big-endian coordinate.
  defp pad32(bin) when byte_size(bin) >= 32, do: binary_part(bin, byte_size(bin) - 32, 32)
  defp pad32(bin), do: :binary.copy(<<0>>, 32 - byte_size(bin)) <> bin
end
