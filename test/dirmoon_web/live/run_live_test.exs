defmodule DirmoonWeb.RunLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.ExpandPhrases

  test "the nine Steps show with their number, name, result and status", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})

    steps =
      %{1 => :done, 2 => :done, 3 => :done, 4 => :done, 5 => :running, 6 => :skipped}
      |> build_run_steps()
      |> Enum.map(&put_result(&1, 1, "Kilkanaście fraz startowych i pytania"))

    run = insert(:run, account: scope.account, steps: steps)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-steps #step-1", "01")
    assert has_element?(view, "#step-1", "Załążki")
    assert has_element?(view, "#step-1", "Kilkanaście fraz startowych i pytania")
    assert has_element?(view, "#step-1-status", "Gotowe")
    assert has_element?(view, "#step-5-status", "W toku")
    assert has_element?(view, "#step-6-status", "Pominięty")
    assert has_element?(view, "#step-7-status", "Czeka")
    assert has_element?(view, "#step-9", "09")
    assert has_element?(view, "#step-9", "Publikacja")
    assert has_element?(view, "#step-9", "Landing na Netlify")
  end

  test "a queued Step shows as waiting", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-8-status", "Czeka")
  end

  test "a Step that finishes while the screen is open updates its row without a reload", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    finish_step(run, 1, "Frazy startowe gotowe do rozwinięcia")
    Research.broadcast_run_updated(run)

    assert has_element?(view, "#step-1", "Frazy startowe gotowe do rozwinięcia")
    assert has_element?(view, "#step-1-status", "Gotowe")
  end

  test "progress of Step 5 shows how many Phrases are checked and a progress bar", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    Research.broadcast_progress(run, progress(insert(:phrase), %{checked: 6, total: 24}))

    assert has_element?(view, "#run-detail", "6 z 24 fraz sprawdzonych")
    assert has_element?(view, "#run-progress[role=progressbar][aria-valuenow='6'][aria-valuemax='24']")
  end

  test "the latest checked Phrases show who holds the top 10, coloured by verdict", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    weak_phrase = insert(:phrase, phrase: unique_phrase_text("wynajem łodzi bez patentu"))
    strong_phrase = insert(:phrase, phrase: unique_phrase_text("wynajem łodzi cennik"))
    Research.broadcast_progress(run, progress(weak_phrase, %{checked: 1, holders: "blogi, fora", verdict: :weak}))
    Research.broadcast_progress(run, progress(strong_phrase, %{checked: 2, holders: "konkurenci", verdict: :strong}))

    assert has_element?(view, "#checked-phrases [data-verdict=weak]", weak_phrase.phrase)
    assert has_element?(view, "#checked-phrases [data-verdict=weak] .text-accent", "blogi, fora")
    assert has_element?(view, "#checked-phrases [data-verdict=strong] .text-warn", "konkurenci")
  end

  test "only the eight latest checked Phrases are listed, newest first", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    phrases = Enum.map(1..10, fn _number -> insert(:phrase, phrase: unique_phrase_text("łódź motorowa")) end)

    phrases
    |> Enum.with_index(1)
    |> Enum.each(fn {phrase, checked} ->
      Research.broadcast_progress(run, progress(phrase, %{checked: checked, total: 10}))
    end)

    entries = view |> render() |> LazyHTML.from_document() |> LazyHTML.query("#checked-phrases [data-verdict]")

    assert Enum.count(entries) == 8
    assert has_element?(view, "#checked-phrases li:first-child", Enum.at(phrases, 9).phrase)
    refute has_element?(view, "#checked-phrases", Enum.at(phrases, 0).phrase)
    refute has_element?(view, "#checked-phrases", Enum.at(phrases, 1).phrase)
  end

  test "phrases checked again after a resume each keep their own row", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    before_stop = insert(:phrase, phrase: unique_phrase_text("czarter jachtu"))
    after_resume = insert(:phrase, phrase: unique_phrase_text("czarter jachtu mazury"))

    Research.broadcast_progress(run, progress(before_stop, %{checked: 1}))
    Research.broadcast_progress(run, progress(after_resume, %{checked: 1}))

    assert has_element?(view, "#checked-phrase-#{before_stop.id}", before_stop.phrase)
    assert has_element?(view, "#checked-phrases li:first-child", after_resume.phrase)
  end

  test "a phrase checked twice is listed once, at the top", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    repeated = insert(:phrase, phrase: unique_phrase_text("czarter jachtu"))
    other = insert(:phrase, phrase: unique_phrase_text("czarter jachtu cena"))

    Research.broadcast_progress(run, progress(repeated, %{checked: 1}))
    Research.broadcast_progress(run, progress(other, %{checked: 2}))
    Research.broadcast_progress(run, progress(repeated, %{checked: 1}))

    entries =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#checked-phrases [data-verdict]")

    assert Enum.count(entries) == 2
    assert has_element?(view, "#checked-phrases li:first-child", repeated.phrase)
  end

  test "the running Step 5 row counts the checked phrases as they come", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-5", "Kto trzyma top 10 dla najlepszych fraz")

    Research.broadcast_progress(run, progress(insert(:phrase), %{checked: 4, total: 10}))

    assert has_element?(view, "#step-5", "4 z 10 fraz sprawdzonych")
    refute has_element?(view, "#step-5", "Kto trzyma top 10 dla najlepszych fraz")
  end

  test "the status row shows the sentence built from the run's state", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(
             view,
             "#run-status-line",
             "Sprawdzam, kto odpowiada na najlepsze frazy. Po kroku 7 wybierasz niszę."
           )
  end

  test "the API Cost shows what the run's recorded requests cost so far", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    insert(:api_request, run: run, cost: Decimal.new("0.075"))
    insert(:api_request, run: run, cost: Decimal.new("0.0025"))
    insert(:api_request, cost: Decimal.new("3"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-cost", "Koszt API: $0,08")
  end

  test "a run with no recorded requests costs zero dollars", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-cost", "Koszt API: $0,00")
  end

  test "clicking stop stops the run and offers to resume it", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    view |> element("#stop-run") |> render_click()

    assert Repo.reload!(run).status == :stopped
    assert has_element?(view, "#resume-run", "Wznów")
    refute has_element?(view, "#stop-run")
  end

  test "clicking resume on a stopped run runs it again from the Step it stopped at", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    view |> element("#stop-run") |> render_click()

    view |> element("#resume-run") |> render_click()

    assert Repo.reload!(run).status == :running
    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
    assert has_element?(view, "#stop-run", "Zatrzymaj")
    refute has_element?(view, "#resume-run")
  end

  test "when Step 7 finishes while the screen is open the User is taken to the results", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running)
    run = insert(:run, account: scope.account, steps: build_run_steps(statuses))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    finish_step(run, 7, "Nisze ocenione")
    run |> Ecto.Changeset.change(status: :awaiting_choice) |> Repo.update!()
    Research.broadcast_run_updated(run)

    assert_redirect(view, "/app/runs/#{run.id}/results")
  end

  test "opening a run that already awaits a choice shows a way to the results instead of redirecting", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = Map.new(1..7, &{&1, :done})
    run = insert(:run, account: scope.account, status: :awaiting_choice, steps: build_run_steps(statuses))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-detail #see-results[href='/app/runs/#{run.id}/results']", "Zobacz wyniki")
    assert has_element?(view, "#run-headline", "Wybierz niszę.")
    refute has_element?(view, "#stop-run")
    refute has_element?(view, "#resume-run")
  end

  test "a failed Step shows an error with its reason and the run offers to resume", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})

    steps =
      %{1 => :done, 2 => :failed}
      |> build_run_steps()
      |> Enum.map(&put_error(&1, 2, "Brak danych logowania DataForSEO"))

    run = insert(:run, account: scope.account, status: :failed, steps: steps)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-2-status", "Błąd")
    assert has_element?(view, "#step-2-error", "Brak danych logowania DataForSEO")
    assert has_element?(view, "#resume-run", "Wznów")
    assert has_element?(view, "#run-headline", "Research przerwany błędem.")
  end

  test "the phrases so far link to the run's results", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#show-phrases[href='/app/runs/#{run.id}/results']", "Pokaż dotychczasowe frazy")
  end

  test "the hero names the run's description, country and city", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})

    run =
      insert(:run,
        account: scope.account,
        description: "Wypożyczalnia rowerów cargo. Dostawa pod drzwi.",
        city: "Toruń",
        steps: build_run_steps(%{1 => :running})
      )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-context", "Wypożyczalnia rowerów cargo · Polska · Toruń")
    assert has_element?(view, "#run-headline", "Research w toku.")
    assert has_element?(view, "#run-panel [data-part=context]", "dirmoon / Wypożyczalnia rowerów cargo")
  end

  test "a run in another Account is not found and nothing of it is shown", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, steps: build_run_steps(%{1 => :running}))

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, ~p"/app/runs/#{run}")
    assert flash["error"] == "Nie znaleziono researchu"
  end

  test "a malformed run id is not found", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, "/app/runs/nie-ma-takiego")
    assert flash["error"] == "Nie znaleziono researchu"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    run = insert(:run, steps: build_run_steps(%{1 => :running}))

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs/#{run}")
  end

  test "a run stopped elsewhere shows as stopped after the update arrives", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    {:ok, %Run{}} = Research.stop_run(scope, run.id)

    assert has_element?(view, "#run-status-line", "Zatrzymałem research na kroku 2. Możesz go wznowić.")
    assert has_element?(view, "#run-headline", "Research zatrzymany.")
  end

  defp running_step(number) do
    1..(number - 1)
    |> Map.new(&{&1, :done})
    |> Map.put(number, :running)
  end

  defp progress(phrase, overrides) do
    Map.merge(
      %{
        step: 5,
        checked: 1,
        total: 30,
        phrase: phrase.phrase,
        keyword_id: phrase.id,
        holders: "blogi",
        verdict: :weak
      },
      overrides
    )
  end

  defp finish_step(run, number, result) do
    RunStep
    |> Repo.get_by!(run_id: run.id, number: number)
    |> RunStep.finish_changeset(%{status: :done, result: result})
    |> Repo.update!()
  end

  defp put_result(%RunStep{number: number} = step, number, result), do: %{step | result: result}
  defp put_result(step, _number, _result), do: step

  defp put_error(%RunStep{number: number} = step, number, error), do: %{step | error: error}
  defp put_error(step, _number, _error), do: step
end
