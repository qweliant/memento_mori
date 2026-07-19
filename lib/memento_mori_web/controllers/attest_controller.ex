defmodule MementoMoriWeb.AttestController do
  @moduledoc """
  The public trustee attestation page. Reached via a signed capability link — no
  account required. A trustee reviews the request and attests that the capsule's
  trigger condition has been met; their attestation counts toward the quorum.
  """
  use MementoMoriWeb, :controller

  alias MementoMori.Vault
  alias MementoMoriWeb.CapabilityToken

  def show(conn, %{"token" => token}) do
    with {:ok, %{capsule_id: capsule_id, trustee_id: trustee_id}} <-
           CapabilityToken.verify_trustee(token),
         {:ok, ctx} <- Vault.get_trustee_context(capsule_id, trustee_id) do
      render(conn, :show,
        token: token,
        trustee: ctx.trustee,
        capsule: ctx.capsule,
        attested?: ctx.attested?
      )
    else
      _ -> conn |> put_status(:not_found) |> render(:invalid)
    end
  end

  @signature_errors [
    :bad_signature,
    :key_mismatch,
    :missing,
    :bad_encoding,
    :missing_attested_at,
    :bad_attested_at
  ]

  def create(conn, %{"token" => token} = params) do
    with {:ok, %{capsule_id: capsule_id, trustee_id: trustee_id}} <-
           CapabilityToken.verify_trustee(token),
         {:ok, _} <- Vault.record_signed_attestation(capsule_id, trustee_id, params) do
      render(conn, :recorded)
    else
      {:error, reason} when reason in @signature_errors ->
        conn |> put_status(:unprocessable_entity) |> render(:signature_error)

      _ ->
        conn |> put_status(:not_found) |> render(:invalid)
    end
  end
end
