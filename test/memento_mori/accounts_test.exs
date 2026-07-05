defmodule MementoMori.AccountsTest do
  use MementoMori.DataCase

  alias MementoMori.Accounts

  import MementoMori.AccountsFixtures
  alias MementoMori.Accounts.{Owner, OwnerToken}

  describe "get_owner_by_email/1" do
    test "does not return the owner if the email does not exist" do
      refute Accounts.get_owner_by_email("unknown@example.com")
    end

    test "returns the owner if the email exists" do
      %{id: id} = owner = owner_fixture()
      assert %Owner{id: ^id} = Accounts.get_owner_by_email(owner.email)
    end
  end

  describe "get_owner_by_email_and_password/2" do
    test "does not return the owner if the email does not exist" do
      refute Accounts.get_owner_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the owner if the password is not valid" do
      owner = owner_fixture() |> set_password()
      refute Accounts.get_owner_by_email_and_password(owner.email, "invalid")
    end

    test "returns the owner if the email and password are valid" do
      %{id: id} = owner = owner_fixture() |> set_password()

      assert %Owner{id: ^id} =
               Accounts.get_owner_by_email_and_password(owner.email, valid_owner_password())
    end
  end

  describe "get_owner!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_owner!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the owner with the given id" do
      %{id: id} = owner = owner_fixture()
      assert %Owner{id: ^id} = Accounts.get_owner!(owner.id)
    end
  end

  describe "register_owner/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_owner(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_owner(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_owner(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = owner_fixture()
      {:error, changeset} = Accounts.register_owner(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_owner(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers owners without password" do
      email = unique_owner_email()
      {:ok, owner} = Accounts.register_owner(valid_owner_attributes(email: email))
      assert owner.email == email
      assert is_nil(owner.hashed_password)
      assert is_nil(owner.confirmed_at)
      assert is_nil(owner.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%Owner{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%Owner{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%Owner{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %Owner{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%Owner{})
    end
  end

  describe "change_owner_email/3" do
    test "returns a owner changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_owner_email(%Owner{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_owner_update_email_instructions/3" do
    setup do
      %{owner: owner_fixture()}
    end

    test "sends token through notification", %{owner: owner} do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_owner_update_email_instructions(owner, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert owner_token = Repo.get_by(OwnerToken, token: :crypto.hash(:sha256, token))
      assert owner_token.owner_id == owner.id
      assert owner_token.sent_to == owner.email
      assert owner_token.context == "change:current@example.com"
    end
  end

  describe "update_owner_email/2" do
    setup do
      owner = unconfirmed_owner_fixture()
      email = unique_owner_email()

      token =
        extract_owner_token(fn url ->
          Accounts.deliver_owner_update_email_instructions(
            %{owner | email: email},
            owner.email,
            url
          )
        end)

      %{owner: owner, token: token, email: email}
    end

    test "updates the email with a valid token", %{owner: owner, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_owner_email(owner, token)
      changed_owner = Repo.get!(Owner, owner.id)
      assert changed_owner.email != owner.email
      assert changed_owner.email == email
      refute Repo.get_by(OwnerToken, owner_id: owner.id)
    end

    test "does not update email with invalid token", %{owner: owner} do
      assert Accounts.update_owner_email(owner, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(Owner, owner.id).email == owner.email
      assert Repo.get_by(OwnerToken, owner_id: owner.id)
    end

    test "does not update email if owner email changed", %{owner: owner, token: token} do
      assert Accounts.update_owner_email(%{owner | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Owner, owner.id).email == owner.email
      assert Repo.get_by(OwnerToken, owner_id: owner.id)
    end

    test "does not update email if token expired", %{owner: owner, token: token} do
      {1, nil} = Repo.update_all(OwnerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_owner_email(owner, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Owner, owner.id).email == owner.email
      assert Repo.get_by(OwnerToken, owner_id: owner.id)
    end
  end

  describe "change_owner_password/3" do
    test "returns a owner changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_owner_password(%Owner{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_owner_password(
          %Owner{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_owner_password/2" do
    setup do
      %{owner: owner_fixture()}
    end

    test "validates password", %{owner: owner} do
      {:error, changeset} =
        Accounts.update_owner_password(owner, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{owner: owner} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_owner_password(owner, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{owner: owner} do
      {:ok, {owner, expired_tokens}} =
        Accounts.update_owner_password(owner, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(owner.password)
      assert Accounts.get_owner_by_email_and_password(owner.email, "new valid password")
    end

    test "deletes all tokens for the given owner", %{owner: owner} do
      _ = Accounts.generate_owner_session_token(owner)

      {:ok, {_, _}} =
        Accounts.update_owner_password(owner, %{
          password: "new valid password"
        })

      refute Repo.get_by(OwnerToken, owner_id: owner.id)
    end
  end

  describe "generate_owner_session_token/1" do
    setup do
      %{owner: owner_fixture()}
    end

    test "generates a token", %{owner: owner} do
      token = Accounts.generate_owner_session_token(owner)
      assert owner_token = Repo.get_by(OwnerToken, token: token)
      assert owner_token.context == "session"
      assert owner_token.authenticated_at != nil

      # Creating the same token for another owner should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%OwnerToken{
          token: owner_token.token,
          owner_id: owner_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given owner in new token", %{owner: owner} do
      owner = %{owner | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_owner_session_token(owner)
      assert owner_token = Repo.get_by(OwnerToken, token: token)
      assert owner_token.authenticated_at == owner.authenticated_at
      assert DateTime.compare(owner_token.inserted_at, owner.authenticated_at) == :gt
    end
  end

  describe "get_owner_by_session_token/1" do
    setup do
      owner = owner_fixture()
      token = Accounts.generate_owner_session_token(owner)
      %{owner: owner, token: token}
    end

    test "returns owner by token", %{owner: owner, token: token} do
      assert {session_owner, token_inserted_at} = Accounts.get_owner_by_session_token(token)
      assert session_owner.id == owner.id
      assert session_owner.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return owner for invalid token" do
      refute Accounts.get_owner_by_session_token("oops")
    end

    test "does not return owner for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(OwnerToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_owner_by_session_token(token)
    end
  end

  describe "get_owner_by_magic_link_token/1" do
    setup do
      owner = owner_fixture()
      {encoded_token, _hashed_token} = generate_owner_magic_link_token(owner)
      %{owner: owner, token: encoded_token}
    end

    test "returns owner by token", %{owner: owner, token: token} do
      assert session_owner = Accounts.get_owner_by_magic_link_token(token)
      assert session_owner.id == owner.id
    end

    test "does not return owner for invalid token" do
      refute Accounts.get_owner_by_magic_link_token("oops")
    end

    test "does not return owner for expired token", %{token: token} do
      {1, nil} = Repo.update_all(OwnerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_owner_by_magic_link_token(token)
    end
  end

  describe "login_owner_by_magic_link/1" do
    test "confirms owner and expires tokens" do
      owner = unconfirmed_owner_fixture()
      refute owner.confirmed_at
      {encoded_token, hashed_token} = generate_owner_magic_link_token(owner)

      assert {:ok, {owner, [%{token: ^hashed_token}]}} =
               Accounts.login_owner_by_magic_link(encoded_token)

      assert owner.confirmed_at
    end

    test "returns owner and (deleted) token for confirmed owner" do
      owner = owner_fixture()
      assert owner.confirmed_at
      {encoded_token, _hashed_token} = generate_owner_magic_link_token(owner)
      assert {:ok, {^owner, []}} = Accounts.login_owner_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_owner_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed owner has password set" do
      owner = unconfirmed_owner_fixture()
      {1, nil} = Repo.update_all(Owner, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_owner_magic_link_token(owner)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_owner_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_owner_session_token/1" do
    test "deletes the token" do
      owner = owner_fixture()
      token = Accounts.generate_owner_session_token(owner)
      assert Accounts.delete_owner_session_token(token) == :ok
      refute Accounts.get_owner_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{owner: unconfirmed_owner_fixture()}
    end

    test "sends token through notification", %{owner: owner} do
      token =
        extract_owner_token(fn url ->
          Accounts.deliver_login_instructions(owner, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert owner_token = Repo.get_by(OwnerToken, token: :crypto.hash(:sha256, token))
      assert owner_token.owner_id == owner.id
      assert owner_token.sent_to == owner.email
      assert owner_token.context == "login"
    end
  end

  describe "inspect/2 for the Owner module" do
    test "does not include password" do
      refute inspect(%Owner{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
