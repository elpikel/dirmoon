defmodule Dirmoon.Accounts do
  @moduledoc """
  Users, their Accounts and Memberships, sign-up and magic-link sign-in
  (ADR-0001).
  """

  import Ecto.Query, warn: false

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Accounts.User
  alias Dirmoon.Accounts.UserNotifier
  alias Dirmoon.Accounts.UserToken
  alias Dirmoon.Repo
  alias Ecto.Multi

  @doc """
  Gets a user by email, or nil.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Creates a user with a new Account and their Membership, in one transaction.
  `opts` are `Dirmoon.Accounts.User.email_changeset/3`'s.

  ## Examples

      iex> create_user_with_account(%{email: "new@example.com"})
      {:ok, %User{}}

      iex> create_user_with_account(%{email: "not an email"})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_with_account(attrs, opts \\ []) do
    Multi.new()
    |> Multi.insert(:user, User.email_changeset(%User{}, attrs, opts))
    |> Multi.insert(:account, %Account{})
    |> Multi.insert(:membership, fn %{user: user, account: account} ->
      Membership.changeset(%Membership{user_id: user.id, account_id: account.id})
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes_so_far} -> {:error, changeset}
    end
  end

  @doc ~S"""
  Signs up with an email and sends a sign-in link to it.

  A new email gets a User, a new Account and their Membership. An email that
  already has a User gets only the sign-in link, and the same `:ok`, so the
  caller can't tell the two apart. An invalid email returns
  `{:error, %Ecto.Changeset{}}` and nothing is created.

  ## Examples

      iex> sign_up(%{"email" => "new@example.com"}, &url(~p"/users/log-in/#{&1}"))
      :ok

      iex> sign_up(%{"email" => "not an email"}, &url(~p"/users/log-in/#{&1}"))
      {:error, %Ecto.Changeset{}}

  """
  def sign_up(email_params, login_url_fun) when is_function(login_url_fun, 1) do
    with {:ok, %User{email: email}} <- validate_sign_up_email(email_params),
         {:ok, user} <- find_or_create_user(email),
         {:ok, _sent_email} <- deliver_login_instructions(user, login_url_fun) do
      :ok
    end
  end

  @doc """
  Returns the Account of the user's first Membership, or nil when there is none.
  """
  def account_for_user(%User{id: user_id}) do
    Account
    |> from(as: :account)
    |> join(:inner, [account: account], membership in assoc(account, :memberships), as: :membership)
    |> where([membership: membership], membership.user_id == ^user_id)
    |> order_by([membership: membership], asc: membership.inserted_at, asc: membership.account_id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns the Scope of the user: the user and the Account of their first
  Membership. Raises when the user has no Membership.
  """
  def scope_for_user(%User{} = user) do
    Scope.for_user(user, account_for_user(user))
  end

  @doc """
  Checks whether the user is in sudo mode: their last authentication was no
  more than 20 minutes ago, or the given number of minutes (as a negative
  offset).
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: authenticated_at}, minutes) when is_struct(authenticated_at, DateTime) do
    DateTime.after?(authenticated_at, DateTime.shift(DateTime.utc_now(), minute: minutes))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  See `Dirmoon.Accounts.User.email_changeset/3` for the options.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given email-change token, and deletes the
  user's email-change tokens.
  """
  def update_user_email(user, token) do
    context = UserToken.change_email_context(user.email)

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <- user.id |> UserToken.user_tokens_query(context) |> Repo.delete_all() do
        {:ok, user}
      else
        _invalid_or_failed -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets `{user, token_inserted_at}` for a valid session token, or nil.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user of a valid magic link token, or nil.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _invalid_or_missing -> nil
    end
  end

  @doc """
  Signs the user in with a magic link token.

  An unconfirmed user is confirmed and all their tokens are expired; the
  expired tokens are returned so their sessions can be disconnected. For a
  confirmed user only the magic link token is used up.
  """
  def login_user_by_magic_link(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, user_token} <- Repo.one(query) do
      log_in_found_user(user, user_token)
    else
      _invalid_or_missing -> {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the email-change link to the user's new email.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %Swoosh.Email{}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, UserToken.change_email_context(current_email))

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers a magic link sign-in email to the user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun) when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, UserToken.login_context())
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the given session token.
  """
  def delete_user_session_token(token) do
    token |> UserToken.session_token_query() |> Repo.delete_all()
    :ok
  end

  defp log_in_found_user(%User{confirmed_at: nil} = user, _user_token) do
    user
    |> User.confirm_changeset()
    |> update_user_and_delete_all_tokens()
  end

  defp log_in_found_user(user, user_token) do
    Repo.delete!(user_token)
    {:ok, {user, []}}
  end

  defp validate_sign_up_email(email_params) do
    %User{}
    |> User.email_changeset(email_params, validate_unique: false)
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp find_or_create_user(email) do
    case create_user_with_account(%{email: email}, validate_unique: false) do
      {:ok, user} ->
        {:ok, user}

      {:error, %Ecto.Changeset{errors: [email: {_message, [constraint: :unique, constraint_name: _index]}]}} ->
        {:ok, Repo.get_by!(User, email: email)}
    end
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        user_tokens_query = UserToken.user_tokens_query(user.id)
        tokens_to_expire = Repo.all(user_tokens_query)
        Repo.delete_all(user_tokens_query)

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
