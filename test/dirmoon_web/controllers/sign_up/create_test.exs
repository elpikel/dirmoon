defmodule DirmoonWeb.Controllers.SignUp.CreateTest do
  use DirmoonWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.User
  alias Dirmoon.Repo

  test "signing up with a new email creates a user, their account and membership", %{conn: conn} do
    email = unique_user_email()

    post(conn, ~p"/sign-up", %{"form" => "hero", "user" => %{"email" => email}})

    user = Repo.get_by!(User, email: email)
    membership = Repo.get_by!(Membership, user_id: user.id)
    assert Repo.get!(Account, membership.account_id)
  end

  test "signing up with a new email sends a sign-in link to that address", %{conn: conn} do
    email = unique_user_email()

    post(conn, ~p"/sign-up", %{"form" => "hero", "user" => %{"email" => email}})

    assert_email_sent(fn sent_email ->
      assert sent_email.to == [{"", email}]
      assert sent_email.text_body =~ "/users/log-in/"
    end)
  end

  test "a signed-in user submitting the sign-up form is sent to the app and nothing is created or mailed",
       %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    email = unique_user_email()

    conn = post(conn, ~p"/sign-up", %{"form" => "hero", "user" => %{"email" => email}})

    assert redirected_to(conn) == ~p"/app"
    refute Repo.get_by(User, email: email)
    assert_no_email_sent()
  end

  test "signing up from the hero form brings the visitor back to a confirmation that the link was sent",
       %{conn: conn} do
    email = unique_user_email()

    conn = post(conn, ~p"/sign-up", %{"form" => "hero", "user" => %{"email" => email}})

    assert redirected_to(conn) == ~p"/"

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-hero #sign-up-confirmation-hero") |> squish() ==
             "Wysłaliśmy link logowania na #{email}. Sprawdź skrzynkę."

    assert document |> LazyHTML.query("form#sign-up-form-hero") |> Enum.count() == 0
  end

  test "signing up from the closing form brings the visitor back to the closing band's confirmation",
       %{conn: conn} do
    email = unique_user_email()

    conn = post(conn, ~p"/sign-up", %{"form" => "closing", "user" => %{"email" => email}})

    assert redirected_to(conn) == ~p"/" <> "#closing"

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#closing #sign-up-confirmation-closing") |> squish() ==
             "Wysłaliśmy link logowania na #{email}. Sprawdź skrzynkę."
  end

  test "signing up with an email that already has a User gets the same confirmation and a sign-in link, without a new account",
       %{conn: conn} do
    user = insert(:user)
    account_count = Repo.aggregate(Account, :count)

    conn = post(conn, ~p"/sign-up", %{"form" => "hero", "user" => %{"email" => user.email}})

    assert redirected_to(conn) == ~p"/"
    assert Repo.aggregate(Account, :count) == account_count

    assert_email_sent(fn sent_email ->
      assert sent_email.to == [{"", user.email}]
      assert sent_email.text_body =~ "/users/log-in/"
    end)

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#sign-up-confirmation-hero") |> squish() ==
             "Wysłaliśmy link logowania na #{user.email}. Sprawdź skrzynkę."
  end

  test "signing up with an invalid email shows the error on the submitted form and creates nothing",
       %{conn: conn} do
    user_count = Repo.aggregate(User, :count)
    account_count = Repo.aggregate(Account, :count)

    conn = post(conn, ~p"/sign-up", %{"form" => "closing", "user" => %{"email" => "not an email"}})

    document = conn |> html_response(422) |> LazyHTML.from_document()

    closing_form = LazyHTML.query(document, "form#sign-up-form-closing")
    hero_form = LazyHTML.query(document, "form#sign-up-form-hero")

    assert closing_form |> LazyHTML.query("input[type=email]") |> LazyHTML.attribute("value") == ["not an email"]
    assert squish(closing_form) =~ "musi zawierać @"
    refute squish(hero_form) =~ "musi zawierać @"

    assert Repo.aggregate(User, :count) == user_count
    assert Repo.aggregate(Account, :count) == account_count
    assert_no_email_sent()
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
