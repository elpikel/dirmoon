defmodule DirmoonWeb.Controllers.SignUp.CreateDeliveryFailureTest do
  use DirmoonWeb.ConnCase, async: false

  test "signing up while the mail service is down answers 503 with the error in the form, filled in again",
       %{conn: conn} do
    configured = Application.fetch_env!(:dirmoon, Dirmoon.Mailer)
    Application.put_env(:dirmoon, Dirmoon.Mailer, Keyword.put(configured, :adapter, Dirmoon.UnavailableMailerAdapter))
    on_exit(fn -> Application.put_env(:dirmoon, Dirmoon.Mailer, configured) end)
    email = unique_user_email()

    conn = post(conn, ~p"/sign-up", %{"form" => "closing", "user" => %{"email" => email}})

    document = conn |> html_response(503) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("form#sign-up-form-closing") |> LazyHTML.text() =~
             "We couldn't send the sign-in email. Try again in a moment."

    refute document |> LazyHTML.query("form#sign-up-form-hero") |> LazyHTML.text() =~ "We couldn't send"
    assert document |> LazyHTML.query("#flash-group") |> Enum.count() == 0

    assert document
           |> LazyHTML.query("form#sign-up-form-closing input[type=email]")
           |> LazyHTML.attribute("value") == [email]

    assert document |> LazyHTML.query("#sign-up-confirmation-closing") |> Enum.count() == 0
  end
end
