defmodule MementoMori.Encryption.Vault.Binary do
  @moduledoc """
  Ecto type for a value encrypted at rest via `MementoMori.Encryption.Vault`
  (Cloak AES-256-GCM). Stored as ciphertext in a `:binary` column.
  """
  use Cloak.Ecto.Binary, vault: MementoMori.Encryption.Vault
end

defmodule MementoMori.Encryption.Vault.HashedHMAC do
  @moduledoc """
  Blind-index companion to an encrypted field. A deterministic HMAC of the
  plaintext (e.g. an email) that lets us look a record up by exact value
  without ever storing the plaintext itself.
  """
  use Cloak.Ecto.HMAC, otp_app: :memento_mori, algorithm: :sha256
end
