defmodule DirmoonWeb.SignUpController do
  use DirmoonWeb, :controller

  alias Dirmoon.Accounts
  alias DirmoonWeb.PageHTML

  @invalid_email_message "Enter a valid email address."
  @delivery_failed_message "We couldn't send the sign-in email. Try again in a moment."

  def create(conn, %{"user" => user_params} = params) do
    submitted_form = PageHTML.submitted_sign_up_form_name(params["form"])

    case Accounts.sign_up(user_params, &url(~p"/users/log-in/#{&1}")) do
      :ok ->
        conn
        |> put_flash(:signed_up, PageHTML.sign_up_confirmation_message(user_params["email"]))
        |> redirect(to: PageHTML.sign_up_form_path(submitted_form))

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_landing(PageHTML.sign_up_forms(submitted_form, user_params, @invalid_email_message))

      {:error, _delivery_reason} ->
        conn
        |> put_status(:service_unavailable)
        |> render_landing(PageHTML.sign_up_forms(submitted_form, user_params, @delivery_failed_message))
    end
  end

  defp render_landing(conn, sign_up_forms) do
    conn
    |> put_view(PageHTML)
    |> render(:home, PageHTML.landing_assigns(sign_up_forms))
  end
end
