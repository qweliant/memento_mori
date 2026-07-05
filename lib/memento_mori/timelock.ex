defmodule MementoMori.Timelock do
  @moduledoc """
  Owner-scoped context for drand-timelock sealed messages.

  This context only ever handles ciphertext. Encryption and decryption happen
  client-side (see the `TimelockSeal` / `TimelockOpen` JS hooks); the server's
  job is to durably hold the sealed blob and its unlock metadata.
  """
  import Ecto.Query, warn: false

  alias MementoMori.Repo
  alias MementoMori.Accounts.Scope
  alias MementoMori.Timelock.SealedMessage

  @doc "Lists the current owner's sealed messages, newest first."
  def list_sealed_messages(%Scope{} = scope) do
    Repo.all(
      from m in SealedMessage,
        where: m.owner_id == ^scope.owner.id,
        order_by: [desc: m.inserted_at]
    )
  end

  @doc "Fetches one of the owner's sealed messages, raising if it isn't theirs."
  def get_sealed_message!(%Scope{} = scope, id) do
    Repo.get_by!(SealedMessage, id: id, owner_id: scope.owner.id)
  end

  @doc "Persists a browser-sealed ciphertext for the current owner."
  def create_sealed_message(%Scope{} = scope, attrs) do
    %SealedMessage{}
    |> SealedMessage.changeset(attrs, scope)
    |> Repo.insert()
  end

  @doc "Records that a message was first opened (for the audit trail / UI)."
  def mark_opened(%Scope{} = scope, %SealedMessage{owner_id: owner_id} = message)
      when owner_id == scope.owner.id do
    message
    |> Ecto.Changeset.change(opened_at: message.opened_at || now())
    |> Repo.update()
  end

  @doc "Deletes one of the owner's sealed messages."
  def delete_sealed_message(%Scope{} = scope, %SealedMessage{owner_id: owner_id} = message)
      when owner_id == scope.owner.id do
    Repo.delete(message)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
