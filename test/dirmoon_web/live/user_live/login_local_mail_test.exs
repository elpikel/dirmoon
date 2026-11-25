defmodule DirmoonWeb.UserLive.LoginLocalMailTest do
  use DirmoonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "with the local mail adapter the sign-in page points to the dev mailbox", %{conn: conn} do
    configured = Application.fetch_env!(:dirmoon, Dirmoon.Mailer)
    Application.put_env(:dirmoon, Dirmoon.Mailer, Keyword.put(configured, :adapter, Swoosh.Adapters.Local))
    on_exit(fn -> Application.put_env(:dirmoon, Dirmoon.Mailer, configured) end)

    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#local-mail-adapter-notice a[href='/dev/mailbox']", "dev mailbox")
  end

  test "with any other mail adapter the sign-in page shows no dev mailbox notice", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(view, "#local-mail-adapter-notice")
  end
end
