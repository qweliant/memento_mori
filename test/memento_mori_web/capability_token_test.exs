defmodule MementoMoriWeb.CapabilityTokenTest do
  use ExUnit.Case, async: true

  alias MementoMoriWeb.CapabilityToken

  test "trustee token round-trips" do
    token = CapabilityToken.sign_trustee(%{id: "t1", capsule_id: "c1"})
    assert {:ok, %{trustee_id: "t1", capsule_id: "c1"}} = CapabilityToken.verify_trustee(token)
  end

  test "beneficiary token round-trips" do
    token = CapabilityToken.sign_beneficiary(%{id: "b1", capsule_id: "c1"})
    assert {:ok, %{beneficiary_id: "b1", capsule_id: "c1"}} = CapabilityToken.verify_beneficiary(token)
  end

  test "garbage is rejected" do
    assert {:error, _} = CapabilityToken.verify_trustee("not-a-token")
  end

  test "a trustee token does not verify as a beneficiary token (role separation)" do
    token = CapabilityToken.sign_trustee(%{id: "t1", capsule_id: "c1"})
    assert {:error, _} = CapabilityToken.verify_beneficiary(token)
  end
end
