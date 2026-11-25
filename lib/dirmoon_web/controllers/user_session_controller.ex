defmodule DirmoonWeb.UserSessionController do
  use DirmoonWeb, :controller

  alias Dirmoon.Accounts
  alias DirmoonWeb.UserAuth

  def create(conn, %{"_action" => "confirmed", "user" => user_params}) do
    log_in_with_magic_link(conn, user_params, "Account confirmed. Welcome to dirmoon!")
  end

  def create(conn, %{"user" => user_params}) do
    log_in_with_magic_link(conn, user_params, "Welcome back!")
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  defp log_in_with_magic_link(conn, %{"token" => token} = user_params, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The sign-in link is invalid or has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
