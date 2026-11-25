defmodule DirmoonWeb.RunLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.ExpandPhrases

  test "the eight Steps show with their number, name, result and status", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    steps =
      %{1 => :done, 2 => :done, 3 => :done, 4 => :done, 5 => :running, 6 => :skipped}
      |> build_run_steps()
      |> Enum.map(&put_result(&1, 1, "A dozen seed phrases and questions"))

    run = insert(:run, account: scope.account, steps: steps)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-steps #step-1", "01")
    assert has_element?(view, "#step-1", "Seeds")
    assert has_element?(view, "#step-1", "A dozen seed phrases and questions")
    assert has_element?(view, "#step-1-status", "Done")
    assert has_element?(view, "#step-5-status", "In progress")
    assert has_element?(view, "#step-6-status", "Skipped")
    assert has_element?(view, "#step-7-status", "Waiting")
    assert has_element?(view, "#step-8", "08")
    assert has_element?(view, "#step-8", "Brief")
    refute has_element?(view, "#step-8", "content")
    assert has_element?(view, "#step-8", "After you choose a niche")
    assert has_element?(view, "#run-steps > li:last-child#step-8")
    refute has_element?(view, "#step-9")
  end

  test "a queued Step shows as waiting", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-8-status", "Waiting")
  end

  test "a Step that finishes while the screen is open updates its row without a reload", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    finish_step(run, 1, "Seed phrases ready to expand")
    Research.broadcast_run_updated(run)

    assert has_element?(view, "#step-1", "Seed phrases ready to expand")
    assert has_element?(view, "#step-1-status", "Done")
  end

  test "progress of Step 5 shows how many Phrases are checked and a progress bar", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    Research.broadcast_progress(run, progress(insert(:phrase), %{checked: 6, total: 24}))

    assert has_element?(view, "#run-detail", "6 of 24 phrases checked")
    assert has_element?(view, "#run-progress[role=progressbar][aria-valuenow='6'][aria-valuemax='24']")
  end

  test "the latest checked Phrases show who holds the top 10, coloured by verdict", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    weak_phrase = insert(:phrase, phrase: unique_phrase_text("wynajem łodzi bez patentu"))
    strong_phrase = insert(:phrase, phrase: unique_phrase_text("wynajem łodzi cennik"))

    Research.broadcast_progress(
      run,
      progress(weak_phrase, %{checked: 1, holders: "guides and blogs, forums", verdict: :weak})
    )

    Research.broadcast_progress(
      run,
      progress(strong_phrase, %{checked: 2, holders: "businesses like yours", verdict: :strong})
    )

    assert has_element?(view, "#checked-phrases [data-verdict=weak]", weak_phrase.phrase)
    assert has_element?(view, "#checked-phrases [data-verdict=weak] .text-accent", "guides and blogs, forums")
    assert has_element?(view, "#checked-phrases [data-verdict=strong] .text-warn", "businesses like yours")
  end

  test "only the eight latest checked Phrases are listed, newest first", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    phrases = Enum.map(1..10, fn _number -> insert(:phrase, phrase: unique_phrase_text("łódź motorowa") <> " rejs") end)

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
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
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
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
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
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-5", "Who holds the top 10 for the best phrases")

    Research.broadcast_progress(run, progress(insert(:phrase), %{checked: 4, total: 10}))

    assert has_element?(view, "#step-5", "4 of 10 phrases checked")
    refute has_element?(view, "#step-5", "Who holds the top 10 for the best phrases")
  end

  test "the status row shows the sentence built from the run's state", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(
             view,
             "#run-status-line",
             "I'm checking who ranks for the best phrases. After step 7 you choose a niche."
           )
  end

  test "the API Cost shows what the run's recorded requests cost so far", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    insert(:api_request, run: run, cost: Decimal.new("0.075"))
    insert(:api_request, run: run, cost: Decimal.new("0.0025"))
    insert(:api_request, cost: Decimal.new("3"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-cost", "API cost: $0.08")
  end

  test "a run with no recorded requests costs zero dollars", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-cost", "API cost: $0.00")
  end

  test "clicking stop stops the run and offers to resume it", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    view |> element("#stop-run") |> render_click()

    assert Repo.reload!(run).status == :stopped
    assert has_element?(view, "#resume-run", "Resume")
    refute has_element?(view, "#stop-run")
  end

  test "clicking resume on a stopped run runs it again from the Step it stopped at", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    view |> element("#stop-run") |> render_click()

    view |> element("#resume-run") |> render_click()

    assert Repo.reload!(run).status == :running
    assert_enqueued(worker: ExpandPhrases, args: %{run_id: run.id})
    assert has_element?(view, "#stop-run", "Stop")
    refute has_element?(view, "#resume-run")
  end

  test "when Step 7 finishes while the screen is open the User is taken to the results", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running)
    run = insert(:run, account: scope.account, steps: build_run_steps(statuses))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    finish_step(run, 7, "Niches scored")
    run |> Ecto.Changeset.change(status: :awaiting_choice) |> Repo.update!()
    Research.broadcast_run_updated(run)

    assert_redirect(view, "/app/runs/#{run.id}/results")
  end

  test "opening a run that already awaits a choice shows a way to the results instead of redirecting", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    statuses = Map.new(1..7, &{&1, :done})
    run = insert(:run, account: scope.account, status: :awaiting_choice, steps: build_run_steps(statuses))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-detail #see-results[href='/app/runs/#{run.id}/results']", "See results")
    assert has_element?(view, "#run-status-line", "The niches are scored. Choose one and I'll write a brief for it.")
    refute has_element?(view, "#stop-run")
    refute has_element?(view, "#resume-run")
  end

  test "a failed Step shows an error with its reason and the run offers to resume", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    steps =
      %{1 => :done, 2 => :failed}
      |> build_run_steps()
      |> Enum.map(&put_error(&1, 2, "No DataForSEO credentials"))

    run = insert(:run, account: scope.account, status: :failed, steps: steps)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-2-status", "Failed")
    assert has_element?(view, "#step-2-error", "No DataForSEO credentials")
    assert has_element?(view, "#resume-run", "Resume")
    assert has_element?(view, "#run-status-line", "Step 2 failed: No DataForSEO credentials.")
  end

  test "the phrases so far link to the run's results", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#show-phrases[href='/app/runs/#{run.id}/results']", "Show phrases so far")
  end

  test "the top bar names the run's description, country and city, with no hero on the screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    run =
      insert(:run,
        account: scope.account,
        description: "Wypożyczalnia rowerów cargo. Dostawa pod drzwi.",
        city: "Toruń",
        steps: build_run_steps(%{1 => :running})
      )

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#app-context", "/ Wypożyczalnia rowerów cargo · Poland · Toruń")
    assert has_element?(view, "#app-note", "New idea")
    assert has_element?(view, "#app-nav #nav-runs[aria-current=page]")
    assert has_element?(view, "#app-main #run #run-steps")
    assert has_element?(view, "#app-main #run #run-detail")
    refute has_element?(view, "#run-headline")
    refute has_element?(view, "#run-panel")
  end

  test "a run in another Account is not found and nothing of it is shown", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, steps: build_run_steps(%{1 => :running}))

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, ~p"/app/runs/#{run}")
    assert flash["error"] == "Research not found"
  end

  test "a malformed run id is not found", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, "/app/runs/nie-ma-takiego")
    assert flash["error"] == "Research not found"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    run = insert(:run, steps: build_run_steps(%{1 => :running}))

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs/#{run}")
  end

  test "a run stopped elsewhere shows as stopped after the update arrives", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    {:ok, %Run{}} = Research.stop_run(scope, run.id)

    assert has_element?(view, "#run-status-line", "I stopped the research at step 2. You can resume it.")
  end

  test "progress of a Step other than Step 5 changes nothing on the screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(3)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    Research.broadcast_progress(run, progress(insert(:phrase), %{step: 3, checked: 2, total: 9}))

    assert has_element?(view, "#run-status-line", "I'm checking the volume and CPC of every phrase.")
    refute has_element?(view, "#run-progress")
  end

  test "progress of Step 5 with nothing to check shows an empty progress bar", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(running_step(5)))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    Research.broadcast_progress(run, progress(insert(:phrase), %{checked: 0, total: 0}))

    assert has_element?(view, "#run-progress[aria-valuemax='0'] > div[style='width: 0%']")
  end

  test "a running run with no Step at work says it is working on the research", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(Map.new(1..7, &{&1, :done})))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-detail", "Working on the research")
  end

  test "a run whose Brief is written awaits a choice and offers the results", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = build_run_steps(Map.new(1..8, &{&1, :done}))
    run = insert(:run, account: scope.account, status: :awaiting_choice, steps: steps)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#step-8-status", "Done")
    assert has_element?(view, "#run-detail", "The niches are scored.")
    assert has_element?(view, "#run-detail #see-results[href='/app/runs/#{run.id}/results']")
  end

  test "a run stopped after its last chained Step offers to finish the research", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, status: :stopped, steps: build_run_steps(Map.new(1..7, &{&1, :done})))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")

    assert has_element?(view, "#run-detail", "Resume and I'll finish the research.")
    assert has_element?(view, "#resume-run")
  end

  test "clicking stop on a run that stopped meanwhile shows why and offers to resume", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :done, 2 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    set_status_quietly(run, :stopped)

    view |> element("#stop-run") |> render_click()

    assert has_element?(view, "#flash-error", "The research is no longer running.")
    assert has_element?(view, "#resume-run")
  end

  test "clicking resume on a run that is running again meanwhile shows why and offers to stop", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})

    run =
      insert(:run, account: scope.account, status: :stopped, steps: build_run_steps(%{1 => :done, 2 => :waiting}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    set_status_quietly(run, :running)

    view |> element("#resume-run") |> render_click()

    assert has_element?(view, "#flash-error", "This research can't be resumed now.")
    assert has_element?(view, "#stop-run")
    refute_enqueued(worker: ExpandPhrases)
  end

  test "clicking stop on a run deleted meanwhile goes back to the runs with a not-found error", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    Repo.delete!(run)

    view |> element("#stop-run") |> render_click()

    assert {"/app/runs", %{"error" => "Research not found"}} = assert_redirect(view)
  end

  test "an update for a run deleted meanwhile goes back to the runs with a not-found error", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, steps: build_run_steps(%{1 => :running}))
    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}")
    Repo.delete!(run)

    Research.broadcast_run_updated(run)

    assert {"/app/runs", %{"error" => "Research not found"}} = assert_redirect(view)
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
        holders: "guides and blogs",
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

  defp set_status_quietly(run, status) do
    run |> Ecto.Changeset.change(status: status) |> Repo.update!()
  end
end
