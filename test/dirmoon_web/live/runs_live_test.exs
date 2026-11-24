defmodule DirmoonWeb.RunsLiveTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the Account's runs are listed newest first", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    oldest = insert(:run, account: scope.account, inserted_at: ~U[2026-10-02 09:00:00Z])
    newest = insert(:run, account: scope.account, inserted_at: ~U[2026-11-20 09:00:00Z])
    middle = insert(:run, account: scope.account, inserted_at: ~U[2026-11-01 09:00:00Z])

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    row_ids =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#runs > li")
      |> LazyHTML.attribute("id")
      |> Enum.reject(&(&1 == "runs-empty"))

    assert row_ids == ["runs-#{newest.id}", "runs-#{middle.id}", "runs-#{oldest.id}"]
  end

  test "a row shows the description's first sentence, mode, location, status, date and cost", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    run =
      insert(:run,
        account: scope.account,
        description: "Wypożyczalnia rowerów cargo. Dowozimy rowery pod dom.",
        city: "Toruń",
        status: :running,
        inserted_at: ~U[2026-11-03 12:00:00Z]
      )

    insert(:api_request, run: run, cost: Decimal.new("0.075"))
    insert(:api_request, run: run, cost: Decimal.new("0.0025"))
    insert(:api_request, cost: Decimal.new("4"))

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs-#{run.id}", "Wypożyczalnia rowerów cargo")
    refute has_element?(view, "#runs-#{run.id}", "Dowozimy rowery pod dom")
    assert has_element?(view, "#runs-#{run.id}", "Nowy pomysł")
    assert has_element?(view, "#runs-#{run.id}", "Polska · Toruń")
    assert has_element?(view, "#runs-#{run.id}-status", "W toku")
    assert has_element?(view, "#runs-#{run.id}", "03.11.2026")
    assert has_element?(view, "#runs-#{run.id}-cost", "$0,08")
  end

  test "an Existing Site run shows its domain next to the mode", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "rowery-cargo.example")

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs-#{run.id}", "Istniejąca strona")
    assert has_element?(view, "#runs-#{run.id}", "rowery-cargo.example")
  end

  test "a run with no recorded requests shows zero dollars", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs-#{run.id}-cost", "$0,00")
  end

  test "each status shows its Polish label", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    labels = %{
      running: "W toku",
      stopped: "Zatrzymany",
      failed: "Błąd",
      awaiting_choice: "Czeka na wybór",
      done: "Gotowy"
    }

    runs = Map.new(labels, fn {status, _label} -> {status, insert(:run, account: scope.account, status: status)} end)

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    for {status, label} <- labels do
      assert has_element?(view, "#runs-#{runs[status].id}-status", label)
    end
  end

  test "runs before Step 7 has finished link to the run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    runs = Enum.map([:running, :stopped, :failed], &insert(:run, account: scope.account, status: &1))

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    for run <- runs do
      assert has_element?(view, ~s|#runs-#{run.id} a[href="/app/runs/#{run.id}"]|)
    end
  end

  test "runs whose Step 7 has finished link to their results, whatever their status", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    scored = 1..7 |> Map.new(&{&1, :done}) |> build_run_steps()
    writing_brief = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()

    runs = [
      insert(:run, account: scope.account, status: :awaiting_choice, steps: scored),
      insert(:run, account: scope.account, status: :done, steps: build_run_steps(Map.new(1..9, &{&1, :done}))),
      insert(:run, account: scope.account, status: :running, steps: writing_brief)
    ]

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    for run <- runs do
      assert has_element?(view, ~s|#runs-#{run.id} a[href="/app/runs/#{run.id}/results"]|)
    end
  end

  test "the status row sums up the list in one sentence and counts the runs", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    insert(:run, account: scope.account, status: :done)
    insert(:run, account: scope.account, status: :awaiting_choice)

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs-status-line", "Masz 2 researche: 1 czeka na wybór niszy.")
    assert has_element?(view, "#app-note", "2 researche")
    assert has_element?(view, "#app-context", "/ wyniki")
    assert has_element?(view, "#app-main #runs-screen #runs")
    refute has_element?(view, "#runs-headline")
  end

  test "another Account's runs are not listed", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    own = insert(:run, account: scope.account)
    foreign = insert(:run)

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs-#{own.id}")
    refute has_element?(view, "#runs-#{foreign.id}")
  end

  test "with no runs the list invites the User to start one", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    insert(:run)

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, "#runs #runs-empty")
    assert has_element?(view, ~s|#runs-empty a#start-first-research[href="/app/research/new"]|)
    assert has_element?(view, "#runs-status-line", "Nie mam jeszcze żadnego researchu.")
  end

  test "the Wyniki nav link is marked as the current page", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/runs")

    assert has_element?(view, ~s|nav a[href="/app/runs"][aria-current="page"]|, "Wyniki")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs")
  end
end
