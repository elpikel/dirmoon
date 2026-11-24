defmodule Dirmoon.AccountsHelpers do
  @moduledoc """
  Test helpers for sign-in tokens: reading the token out of a sent email,
  issuing a magic link token directly, and ageing stored tokens.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.UserToken
  alias Dirmoon.Repo

  def extract_user_token(deliver_fun) do
    {:ok, captured_email} = deliver_fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_before, token | _after] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, UserToken.login_context())
    Repo.insert!(user_token)
    %{token: encoded_token, hashed_token: user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    shifted_at = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    token
    |> stored_token_query()
    |> Repo.update_all(set: [inserted_at: shifted_at, authenticated_at: shifted_at])
  end

  def override_token_authenticated_at(token, authenticated_at) do
    token
    |> stored_token_query()
    |> Repo.update_all(set: [authenticated_at: authenticated_at])
  end

  defp stored_token_query(token) do
    UserToken
    |> from(as: :user_token)
    |> where([user_token: user_token], user_token.token == ^token)
  end
end
