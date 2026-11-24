defmodule Dirmoon.Accounts.UserToken do
  @moduledoc """
  Session tokens (stored as is, kept in the signed session cookie) and email
  tokens (stored hashed, sent as magic links or email-change links).
  """
  use Ecto.Schema

  import Ecto.Query

  alias Dirmoon.Accounts.User

  @hash_algorithm :sha256
  @rand_size 32

  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  @session_context "session"
  @login_context "login"

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  The token context of a sign-in (magic link) email.
  """
  def login_context, do: @login_context

  @doc """
  The token context of an email-change link sent while the user's email is `current_email`.
  """
  def change_email_context(current_email), do: "change:#{current_email}"

  @doc """
  Builds a session token. Session tokens live in the signed session cookie,
  so they are stored unhashed; storing them lets single sessions be expired.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    authenticated_at = user.authenticated_at || DateTime.utc_now(:second)

    {token, %__MODULE__{token: token, context: @session_context, user_id: user.id, authenticated_at: authenticated_at}}
  end

  @doc """
  Returns the query for the user of a session token younger than the session
  validity, as `{user, token_inserted_at}` with the token's `authenticated_at`
  on the user.
  """
  def verify_session_token_query(token) do
    query =
      token
      |> by_token_and_context_query(@session_context)
      |> join(:inner, [user_token: user_token], user in assoc(user_token, :user), as: :user)
      |> where([user_token: user_token], user_token.inserted_at > ago(@session_validity_in_days, "day"))
      |> select(
        [user_token: user_token, user: user],
        {%{user | authenticated_at: user_token.authenticated_at}, user_token.inserted_at}
      )

    {:ok, query}
  end

  @doc """
  Returns the query for the given session token.
  """
  def session_token_query(token), do: by_token_and_context_query(token, @session_context)

  @doc """
  Returns the query for every token of the given user, optionally in one context.
  """
  def user_tokens_query(user_id) do
    __MODULE__
    |> from(as: :user_token)
    |> where([user_token: user_token], user_token.user_id == ^user_id)
  end

  def user_tokens_query(user_id, context) do
    user_id
    |> user_tokens_query()
    |> where([user_token: user_token], user_token.context == ^context)
  end

  @doc """
  Builds an email token and its hash. The raw token is emailed, only its
  hash is stored, and it is bound to the email it was sent to.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed_token, context: context, sent_to: user.email, user_id: user.id}}
  end

  @doc """
  Returns the query for `{user, token}` of a magic link token younger than its
  validity and still matching the user's email.
  """
  def verify_magic_link_token_query(token) do
    with {:ok, hashed_token} <- decode_and_hash(token) do
      query =
        hashed_token
        |> by_token_and_context_query(@login_context)
        |> join(:inner, [user_token: user_token], user in assoc(user_token, :user), as: :user)
        |> where(
          [user_token: user_token],
          user_token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute")
        )
        |> where([user_token: user_token, user: user], user_token.sent_to == user.email)
        |> select([user_token: user_token, user: user], {user, user_token})

      {:ok, query}
    end
  end

  @doc """
  Returns the query for an email-change token younger than its validity.
  The context must start with "change:".
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    with {:ok, hashed_token} <- decode_and_hash(token) do
      query =
        hashed_token
        |> by_token_and_context_query(context)
        |> where(
          [user_token: user_token],
          user_token.inserted_at > ago(@change_email_validity_in_days, "day")
        )

      {:ok, query}
    end
  end

  defp decode_and_hash(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} -> {:ok, :crypto.hash(@hash_algorithm, decoded_token)}
      :error -> :error
    end
  end

  defp by_token_and_context_query(token, context) do
    __MODULE__
    |> from(as: :user_token)
    |> where([user_token: user_token], user_token.token == ^token and user_token.context == ^context)
  end
end
