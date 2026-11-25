defmodule DirmoonWeb.PagesLiveTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the Account's pages are listed newest first", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)
    older = insert(:page, run: run, inserted_at: ~U[2026-11-01 10:00:00Z])
    newer = insert(:page, run: run, inserted_at: ~U[2026-11-20 10:00:00Z])

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages > li:nth-child(2)#pages-#{newer.id}")
    assert has_element?(view, "#pages > li:nth-child(3)#pages-#{older.id}")
  end

  test "each page shows its title, Niche, Mode, status and date", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "kancelaria-testowa.example")
    brief = build(:brief)
    page = insert(:page, run: run, brief: brief, status: :ready, inserted_at: ~U[2026-11-03 09:00:00Z])

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-title", brief.title)
    assert has_element?(view, "#pages-#{page.id}-niche", page.niche.name)
    assert has_element?(view, "#pages-#{page.id}-mode", "Existing site")
    assert has_element?(view, "#pages-#{page.id}-status.rounded-pill", "Ready")
    assert has_element?(view, "#pages-#{page.id}-date", "3 Nov 2026")
  end

  test "a page whose Brief is being written is listed under its Niche's name", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-title", page.niche.name)
    assert has_element?(view, "#pages-#{page.id}-status", "Writing")
  end

  test "a page whose Brief failed shows the error status", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :failed, brief: nil, error: "Błąd testowy")

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-status.text-warn", "Failed")
  end

  test "each page links to its page screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account))

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id} a[href='/app/pages/#{page.id}']")
  end

  test "another Account's pages are not listed", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    own = insert(:page, run: insert(:run, account: scope.account))
    foreign = insert(:page, run: insert(:run))

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{own.id}")
    refute has_element?(view, "#pages-#{foreign.id}")
    assert has_element?(view, "#pages-status-line", "I have 1 brief for your niches.")
  end

  test "with no briefs it invites the User to pick a Niche in the results", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-empty", "Your briefs will show up here.")
    assert has_element?(view, "#pages-empty", "I'll write a brief for it.")
    refute has_element?(view, "#pages-empty", "a page for it")
    assert has_element?(view, "#pages-empty a#go-to-results[href='/app/runs']")

    assert has_element?(
             view,
             "#pages-status-line",
             "No briefs yet. Choose a niche in the results and I'll write a brief for it."
           )
  end

  test "the \"Briefs\" nav link leads here and is marked current, and the screen is called Briefs", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "a[href='/app/pages'][aria-current=page]", "Briefs")
    assert has_element?(view, "#pages-screen h1", "Briefs")
    assert has_element?(view, "#app-context", "/ briefs")
    assert page_title(view) =~ "Briefs"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/pages")
  end
end
