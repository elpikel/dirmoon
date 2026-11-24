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

  test "each page shows its title, Niche, Mode, status, published URL and date", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "kancelaria-testowa.example")
    brief = build(:brief)
    url = "https://#{brief.slug}.example"

    page =
      insert(:page,
        run: run,
        brief: brief,
        status: :published,
        published_url: url,
        inserted_at: ~U[2026-11-03 09:00:00Z]
      )

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-title", brief.title)
    assert has_element?(view, "#pages-#{page.id}-niche", page.niche.name)
    assert has_element?(view, "#pages-#{page.id}-mode", "Istniejąca strona")
    assert has_element?(view, "#pages-#{page.id}-status", "Opublikowana")
    assert has_element?(view, "#pages-#{page.id}-url", url)
    assert has_element?(view, "#pages-#{page.id}-date", "03.11.2026")
  end

  test "a page whose Brief is being written is listed under its Niche's name", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-title", page.niche.name)
    assert has_element?(view, "#pages-#{page.id}-status", "Piszę")
    refute has_element?(view, "#pages-#{page.id}-url")
  end

  test "a page whose Brief failed shows the error status", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :failed, brief: nil, error: "Błąd testowy")

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-#{page.id}-status.text-warn", "Błąd")
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
    assert has_element?(view, "#pages-status-line", "Mam 1 stronę dla Twoich nisz.")
  end

  test "with no pages it invites the User to pick a Niche in the results", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "#pages-empty")
    assert has_element?(view, "#pages-empty a#go-to-results[href='/app/runs']")

    assert has_element?(
             view,
             "#pages-status-line",
             "Nie mam jeszcze żadnej strony. Wybierz niszę w wynikach, a napiszę dla niej brief."
           )
  end

  test "the \"Strony\" nav link leads here and is marked current", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/pages")

    assert has_element?(view, "a[href='/app/pages'][aria-current=page]", "Strony")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/pages")
  end
end
