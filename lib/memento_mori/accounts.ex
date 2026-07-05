defmodule MementoMori.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias MementoMori.Repo

  alias MementoMori.Accounts.{Owner, OwnerToken, OwnerNotifier}

  ## Database getters

  @doc """
  Gets a owner by email.

  ## Examples

      iex> get_owner_by_email("foo@example.com")
      %Owner{}

      iex> get_owner_by_email("unknown@example.com")
      nil

  """
  def get_owner_by_email(email) when is_binary(email) do
    Repo.get_by(Owner, email: email)
  end

  @doc """
  Gets a owner by email and password.

  ## Examples

      iex> get_owner_by_email_and_password("foo@example.com", "correct_password")
      %Owner{}

      iex> get_owner_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_owner_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    owner = Repo.get_by(Owner, email: email)
    if Owner.valid_password?(owner, password), do: owner
  end

  @doc """
  Gets a single owner.

  Raises `Ecto.NoResultsError` if the Owner does not exist.

  ## Examples

      iex> get_owner!(123)
      %Owner{}

      iex> get_owner!(456)
      ** (Ecto.NoResultsError)

  """
  def get_owner!(id), do: Repo.get!(Owner, id)

  ## Owner registration

  @doc """
  Registers a owner.

  ## Examples

      iex> register_owner(%{field: value})
      {:ok, %Owner{}}

      iex> register_owner(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_owner(attrs) do
    %Owner{}
    |> Owner.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the owner is in sudo mode.

  The owner is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(owner, minutes \\ -20)

  def sudo_mode?(%Owner{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_owner, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the owner email.

  See `MementoMori.Accounts.Owner.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_owner_email(owner)
      %Ecto.Changeset{data: %Owner{}}

  """
  def change_owner_email(owner, attrs \\ %{}, opts \\ []) do
    Owner.email_changeset(owner, attrs, opts)
  end

  @doc """
  Updates the owner email using the given token.

  If the token matches, the owner email is updated and the token is deleted.
  """
  def update_owner_email(owner, token) do
    context = "change:#{owner.email}"

    Repo.transact(fn ->
      with {:ok, query} <- OwnerToken.verify_change_email_token_query(token, context),
           %OwnerToken{sent_to: email} <- Repo.one(query),
           {:ok, owner} <- Repo.update(Owner.email_changeset(owner, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(OwnerToken, where: [owner_id: ^owner.id, context: ^context])) do
        {:ok, owner}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the owner password.

  See `MementoMori.Accounts.Owner.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_owner_password(owner)
      %Ecto.Changeset{data: %Owner{}}

  """
  def change_owner_password(owner, attrs \\ %{}, opts \\ []) do
    Owner.password_changeset(owner, attrs, opts)
  end

  @doc """
  Updates the owner password.

  Returns a tuple with the updated owner, as well as a list of expired tokens.

  ## Examples

      iex> update_owner_password(owner, %{password: ...})
      {:ok, {%Owner{}, [...]}}

      iex> update_owner_password(owner, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_owner_password(owner, attrs) do
    owner
    |> Owner.password_changeset(attrs)
    |> update_owner_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_owner_session_token(owner) do
    {token, owner_token} = OwnerToken.build_session_token(owner)
    Repo.insert!(owner_token)
    token
  end

  @doc """
  Gets the owner with the given signed token.

  If the token is valid `{owner, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_owner_by_session_token(token) do
    {:ok, query} = OwnerToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the owner with the given magic link token.
  """
  def get_owner_by_magic_link_token(token) do
    with {:ok, query} <- OwnerToken.verify_magic_link_token_query(token),
         {owner, _token} <- Repo.one(query) do
      owner
    else
      _ -> nil
    end
  end

  @doc """
  Logs the owner in by magic link.

  There are three cases to consider:

  1. The owner has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The owner has not confirmed their email and no password is set.
     In this case, the owner gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The owner has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_owner_by_magic_link(token) do
    {:ok, query} = OwnerToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%Owner{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%Owner{confirmed_at: nil} = owner, _token} ->
        owner
        |> Owner.confirm_changeset()
        |> update_owner_and_delete_all_tokens()

      {owner, token} ->
        Repo.delete!(token)
        {:ok, {owner, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given owner.

  ## Examples

      iex> deliver_owner_update_email_instructions(owner, current_email, &url(~p"/owners/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_owner_update_email_instructions(
        %Owner{} = owner,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, owner_token} = OwnerToken.build_email_token(owner, "change:#{current_email}")

    Repo.insert!(owner_token)
    OwnerNotifier.deliver_update_email_instructions(owner, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given owner.
  """
  def deliver_login_instructions(%Owner{} = owner, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, owner_token} = OwnerToken.build_email_token(owner, "login")
    Repo.insert!(owner_token)
    OwnerNotifier.deliver_login_instructions(owner, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_owner_session_token(token) do
    Repo.delete_all(from(OwnerToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_owner_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, owner} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(OwnerToken, owner_id: owner.id)

        Repo.delete_all(
          from(t in OwnerToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {owner, tokens_to_expire}}
      end
    end)
  end
end
