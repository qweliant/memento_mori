defmodule MementoMoriWeb.CapabilityToken do
  @moduledoc """
  Signed, scoped capability tokens for the people who don't hold an account:
  trustees (who attest) and beneficiaries (who claim). Each token is a signed
  `Phoenix.Token` binding a role to a specific capsule + party, so possession of
  the link is the authorization — no login required.

  These are bearer capabilities: anyone with the link can act as that party, so
  in production they'd be delivered over a private channel (email) and could add
  proof-of-possession of a keypair. For the PoC the link itself is the capability.
  """
  alias MementoMoriWeb.Endpoint

  @trustee_salt "memento_mori:trustee-attestation:v1"
  @beneficiary_salt "memento_mori:beneficiary-claim:v1"
  # 90 days — these links are meant to survive until a capsule triggers.
  @max_age 60 * 60 * 24 * 90

  def sign_trustee(%{id: trustee_id, capsule_id: capsule_id}) do
    Phoenix.Token.sign(Endpoint, @trustee_salt, %{capsule_id: capsule_id, trustee_id: trustee_id})
  end

  def verify_trustee(token) do
    Phoenix.Token.verify(Endpoint, @trustee_salt, token, max_age: @max_age)
  end

  def sign_beneficiary(%{id: beneficiary_id, capsule_id: capsule_id}) do
    Phoenix.Token.sign(Endpoint, @beneficiary_salt, %{
      capsule_id: capsule_id,
      beneficiary_id: beneficiary_id
    })
  end

  def verify_beneficiary(token) do
    Phoenix.Token.verify(Endpoint, @beneficiary_salt, token, max_age: @max_age)
  end
end
