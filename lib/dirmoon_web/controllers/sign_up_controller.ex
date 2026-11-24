defmodule DirmoonWeb.SignUpController do
  use DirmoonWeb, :controller

  alias Dirmoon.Accounts
  alias DirmoonWeb.PageHTML

  def create(conn, %{"user" => user_params} = params) do
    submitted_form = PageHTML.submitted_sign_up_form_name(params["form"])

    case Accounts.sign_up(user_params, &url(~p"/users/log-in/#{&1}")) do
      :ok ->
        conn
        |> put_flash(:signed_up, PageHTML.sign_up_confirmation_message(user_params["email"]))
        |> redirect(to: PageHTML.sign_up_form_path(submitted_form))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_landing(submitted_form, changeset)

      {:error, _delivery_reason} ->
        conn
        |> put_status(:service_unavailable)
        |> put_flash(:error, "Nie udało się wysłać e-maila z linkiem logowania. Spróbuj ponownie za chwilę.")
        |> render_landing(submitted_form, user_params)
    end
  end

  defp render_landing(conn, submitted_form, changeset_or_params) do
    conn
    |> put_view(PageHTML)
    |> render(:home, sign_up_forms: PageHTML.sign_up_forms(submitted_form, changeset_or_params))
  end
end
