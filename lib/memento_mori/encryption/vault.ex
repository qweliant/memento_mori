defmodule MementoMori.Encryption.Vault do
  @moduledoc """
  Cloak vault for application-level encryption of sensitive fields at rest —
  e.g. beneficiary contact details and wrapped-key material.

  Note the zero-knowledge boundary: capsule Content Encryption Keys (CEKs) are
  never stored here. This vault protects operational metadata, not sealed
  capsule contents, which are encrypted client-side before they ever reach us.
  """
  use Cloak.Vault, otp_app: :memento_mori
end
