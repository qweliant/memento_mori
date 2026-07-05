defmodule MementoMori.VaultFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `MementoMori.Vault` context.
  """

  @doc """
  Generate a capsule.
  """
  def capsule_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        sensitivity_tier: :medium,
        title: "some title"
      })

    {:ok, capsule} = MementoMori.Vault.create_capsule(scope, attrs)
    capsule
  end
end
