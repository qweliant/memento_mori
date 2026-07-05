defmodule MementoMori.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `MementoMori.Accounts` context.
  """

  import Ecto.Query

  alias MementoMori.Accounts
  alias MementoMori.Accounts.Scope

  def unique_owner_email, do: "owner#{System.unique_integer()}@example.com"
  def valid_owner_password, do: "hello world!"

  def valid_owner_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_owner_email()
    })
  end

  def unconfirmed_owner_fixture(attrs \\ %{}) do
    {:ok, owner} =
      attrs
      |> valid_owner_attributes()
      |> Accounts.register_owner()

    owner
  end

  def owner_fixture(attrs \\ %{}) do
    owner = unconfirmed_owner_fixture(attrs)

    token =
      extract_owner_token(fn url ->
        Accounts.deliver_login_instructions(owner, url)
      end)

    {:ok, {owner, _expired_tokens}} =
      Accounts.login_owner_by_magic_link(token)

    owner
  end

  def owner_scope_fixture do
    owner = owner_fixture()
    owner_scope_fixture(owner)
  end

  def owner_scope_fixture(owner) do
    Scope.for_owner(owner)
  end

  def set_password(owner) do
    {:ok, {owner, _expired_tokens}} =
      Accounts.update_owner_password(owner, %{password: valid_owner_password()})

    owner
  end

  def extract_owner_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    MementoMori.Repo.update_all(
      from(t in Accounts.OwnerToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_owner_magic_link_token(owner) do
    {encoded_token, owner_token} = Accounts.OwnerToken.build_email_token(owner, "login")
    MementoMori.Repo.insert!(owner_token)
    {encoded_token, owner_token.token}
  end

  def offset_owner_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    MementoMori.Repo.update_all(
      from(ut in Accounts.OwnerToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
