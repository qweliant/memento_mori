defmodule MementoMori.Vault.CiphertextStore do
  @moduledoc """
  A local, dev/PoC stand-in for Files.com: an opaque blob store for artifact
  ciphertext.

  It never sees plaintext — artifacts are encrypted client-side (via drand
  timelock) before they are handed here. `put!/1` returns an opaque ref that is
  stored on the artifact as `ciphertext_ref`; `get/1` fetches the bytes back so
  the browser can decrypt them. In production this module is the seam where a
  real Files.com adapter would slot in.
  """

  @doc "Directory the ciphertext blobs live in."
  def dir do
    Application.get_env(:memento_mori, :ciphertext_store_dir) ||
      Path.join(:code.priv_dir(:memento_mori), "ciphertext_store")
  end

  @doc "Stores an opaque ciphertext blob, returning its ref."
  def put!(bytes) when is_binary(bytes) do
    ref = Ecto.UUID.generate()
    File.mkdir_p!(dir())
    File.write!(path(ref), bytes)
    ref
  end

  @doc "Fetches a ciphertext blob by ref."
  def get(ref) when is_binary(ref), do: File.read(path(ref))

  @doc "Deletes a ciphertext blob by ref."
  def delete(ref) when is_binary(ref), do: File.rm(path(ref))

  defp path(ref), do: Path.join(dir(), ref)
end
