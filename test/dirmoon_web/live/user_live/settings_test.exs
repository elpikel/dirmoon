defmodule DirmoonWeb.UserLive.SettingsTest do
  use DirmoonWeb.ConnCase, async: true

  import Dirmoon.AccountsHelpers
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Dirmoon.Accounts

  test "the settings page shows the email form inside the app layout", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/users/settings")

    assert has_element?(view, "[data-layout=app]")
    assert has_element?(view, "#settings-title", "Ustawienia")
    assert has_element?(view, ~s(#email-form input[name="user[email]"][value="#{user.email}"]))
    assert has_element?(view, "#email-submit[data-variant=dark]", "Zmień e-mail")
  end

  test "a signed-out visitor is redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/settings")

    assert path == ~p"/users/log-in"
    assert %{"error" => "Zaloguj się, aby otworzyć tę stronę."} = flash
  end

  test "a user who signed in more than 10 minutes ago must sign in again", %{conn: conn} do
    eleven_minutes_ago = DateTime.shift(DateTime.utc_now(:second), minute: -11)
    %{conn: conn} = register_and_log_in_user(%{conn: conn, token_authenticated_at: eleven_minutes_ago})

    assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/settings")

    assert path == ~p"/users/log-in"
    assert %{"error" => "Zaloguj się ponownie, aby otworzyć tę stronę."} = flash
  end

  test "submitting a new email sends a confirmation link to it and keeps the old email for now", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    new_email = unique_user_email()
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> form("#email-form", %{"user" => %{"email" => new_email}}) |> render_submit()

    assert has_element?(view, "#flash-info", "Wysłaliśmy link potwierdzający na nowy adres.")
    assert_email_sent(to: new_email, subject: "Potwierdź nowy adres e-mail")
    assert Accounts.get_user_by_email(user.email)
  end

  test "an invalid email shows an error while typing", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> element("#email-form") |> render_change(%{"user" => %{"email" => "with spaces"}})

    assert has_element?(view, "#email-form", "musi zawierać @ i nie może mieć spacji")
  end

  test "submitting the same email shows an error", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> form("#email-form", %{"user" => %{"email" => user.email}}) |> render_submit()

    assert has_element?(view, "#email-form", "to ten sam adres")
    assert_no_email_sent()
  end

  test "submitting an email another user registered shows the same confirmation message and no error", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    other_user = insert(:user)
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> form("#email-form", %{"user" => %{"email" => other_user.email}}) |> render_submit()

    assert has_element?(view, "#flash-info", "Wysłaliśmy link potwierdzający na nowy adres.")
    refute has_element?(view, "#email-form .hero-exclamation-circle")
  end

  test "a blank email shows the Polish required-field error while typing", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> element("#email-form") |> render_change(%{"user" => %{"email" => ""}})

    assert has_element?(view, "#email-form", "nie może być puste")
    refute has_element?(view, "#email-form", "can't be blank")
  end

  test "an email-change link for an address registered in the meantime changes nothing", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    new_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(%{user | email: new_email}, user.email, url)
      end)

    other_user = insert(:user, email: new_email)

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/settings/confirm-email/#{token}")
    assert path == ~p"/users/settings"
    assert %{"error" => "Link zmiany adresu jest nieprawidłowy albo wygasł."} = flash
    assert Accounts.get_user_by_email(user.email).id == user.id
    assert Accounts.get_user_by_email(new_email).id == other_user.id
  end

  test "an email-change link changes the email once", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    new_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(%{user | email: new_email}, user.email, url)
      end)

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/settings/confirm-email/#{token}")
    assert path == ~p"/users/settings"
    assert %{"info" => "Adres e-mail zmieniony."} = flash
    refute Accounts.get_user_by_email(user.email)
    assert Accounts.get_user_by_email(new_email)

    assert {:error, {:live_redirect, %{flash: flash}}} = live(conn, ~p"/users/settings/confirm-email/#{token}")
    assert %{"error" => "Link zmiany adresu jest nieprawidłowy albo wygasł."} = flash
  end

  test "an invalid email-change link keeps the email", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/users/settings/confirm-email/oops")

    assert path == ~p"/users/settings"
    assert %{"error" => "Link zmiany adresu jest nieprawidłowy albo wygasł."} = flash
    assert Accounts.get_user_by_email(user.email)
  end

  test "an email-change link needs a signed-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users/settings/confirm-email/some-token")

    assert path == ~p"/users/log-in"
  end
end
