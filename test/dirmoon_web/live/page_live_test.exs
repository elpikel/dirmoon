defmodule DirmoonWeb.PageLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Pages
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Workers.WriteBrief

  test "the brief screen shows the page's text in the wide column and the phrases and business details beside it",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#brief-form #brief-text #brief-title")
    assert has_element?(view, "#brief-form #brief-text #brief-slug[value='#{page.brief.slug}']")
    assert has_element?(view, "#brief-form #brief-text #brief-h1[value='#{page.brief.h1}']")
    assert has_element?(view, "#brief-form #brief-text #brief-sections #brief-section-0")
    assert has_element?(view, "#brief-form #brief-text #brief-short-answer")
    assert has_element?(view, "#brief-form #brief-side.bg-app-raised #brief-phrases")
    assert has_element?(view, "#brief-form #brief-side #brief-business #brief-business-name")
    assert has_element?(view, "#brief-screen > #page-actions #save-brief")
  end

  test "the brief screen builds no page: no preview, no template fields and no download", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    refute has_element?(view, "iframe")
    refute has_element?(view, "#download-page")
    refute has_element?(view, "a[href$='/file']")
    refute has_element?(view, "#brief-breadcrumb")
    refute has_element?(view, "#brief-cta-label")
    refute has_element?(view, "#brief-fact-tiles")
    refute has_element?(view, "#brief-plausible-domain")
    refute has_element?(view, "[name='brief[nav_links][]']")
  end

  test "the top bar and status row name the Niche and the Mode, with no hero on the screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#app-note", "Topic: #{page.niche.name} · New idea")
    assert has_element?(view, "#app-nav #nav-pages[aria-current=page]")
    assert has_element?(view, "#app-main #page-screen #brief-form")
    refute has_element?(view, "#page-headline")
    refute has_element?(view, "#page-panel")
  end

  test "the status line counts the Brief's questions and leaves prices and contact data to the User", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Pierwsze?"}, %Brief.Section{question: "Drugie?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(
             view,
             "#page-status-line",
             "I wrote the brief, the plan and the text for one page: it answers 2 customer questions. You fill in the prices and contact details."
           )

    refute has_element?(view, "#page-status-line", "must approve")
  end

  test "an Existing Site page's status line says legal, medical or financial answers need the owner's approval",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope, %{mode: :existing_site, domain: "kancelaria-testowa.example"}))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(
             view,
             "#page-status-line",
             "The business owner must approve legal, medical and financial answers before publishing."
           )
  end

  test "typing in the H1 marks the brief unsaved and saves nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    assert has_element?(view, "#brief-save-state[data-saved]", "Saved")

    view |> form("#brief-form", brief: %{h1: "Nowy nagłówek"}) |> render_change()

    assert has_element?(view, "#brief-h1[value='Nowy nagłówek']")
    assert has_element?(view, "#brief-save-state", "Unsaved changes")
    assert Repo.get!(Page, page.id).brief.h1 == page.brief.h1
  end

  test "saving the Brief persists the edit", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    view
    |> form("#brief-form", brief: %{h1: "Zapisany nagłówek", slug: "zapisany-adres"})
    |> put_submitter("#save-brief")
    |> render_submit()

    saved = Repo.get!(Page, page.id)
    assert saved.brief.h1 == "Zapisany nagłówek"
    assert saved.brief.slug == "zapisany-adres"
    assert has_element?(view, "#brief-save-state", "Saved")
    assert has_element?(view, "#flash-info", "I saved the brief.")
    assert has_element?(view, "#app-context", "/ zapisany-adres")
  end

  test "an invalid field shows its error and saves nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{slug: "Zły Adres!", h1: "Nagłówek, który nie przejdzie"}) |> render_submit()

    assert has_element?(view, "label[for=brief-slug] + p", "has invalid format")
    assert has_element?(view, "#flash-error", "Fix the marked fields of the brief.")
    assert Repo.get!(Page, page.id).brief == page.brief
  end

  test "a section can be added and the new question saved", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_change(%{"brief" => %{"sections_sort" => ["0", "new"]}})

    assert has_element?(view, "#brief-section-1 #brief_sections_1_question")

    view
    |> form("#brief-form", brief: %{sections: %{"1" => %{question: "Dodane pytanie?"}}})
    |> render_submit()

    assert [_first, %Brief.Section{question: "Dodane pytanie?"}] = Repo.get!(Page, page.id).brief.sections
  end

  test "a section can be removed", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Zostaje?"}, %Brief.Section{question: "Do usunięcia?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_change(%{"brief" => %{"sections_drop" => ["1"]}})

    refute has_element?(view, "#brief-section-1")
    assert has_element?(view, "#brief-section-0 input[name='brief[sections][0][question]'][value='Zostaje?']")

    view |> form("#brief-form") |> render_submit()

    assert [%Brief.Section{question: "Zostaje?"}] = Repo.get!(Page, page.id).brief.sections
  end

  test "a section can be moved up", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Pierwsze?"}, %Brief.Section{question: "Drugie?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_change(%{"brief" => %{"sections_move_up" => ["1"]}})

    assert has_element?(view, "#brief-section-0 input[name='brief[sections][0][question]'][value='Drugie?']")
    assert has_element?(view, "#brief-section-1 input[name='brief[sections][1][question]'][value='Pierwsze?']")
  end

  test "dropping every section shows that the Brief needs one", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_submit(%{"brief" => %{"sections_drop" => ["0"]}})

    assert has_element?(view, "#brief-sections-error", "should have at least 1 item(s)")
    assert Repo.get!(Page, page.id).brief.sections == page.brief.sections
  end

  test "the Phrases to cover show as chips with the primary one marked", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    brief = build(:brief, phrases: ["fraza poboczna", "fraza główna"], primary_phrase: "fraza główna")
    page = insert(:page, run: brief_run(scope), brief: brief)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#brief-phrases li:first-child[data-primary]", "fraza główna")
    assert has_element?(view, "#brief-phrases li:not([data-primary])", "fraza poboczna")
  end

  test "the business details are editable and saved with the brief", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    email = unique_user_email()

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    view
    |> form("#brief-form", brief: %{business_name: "Firma Testowa", phone: "+48 500 000 001", email: email})
    |> render_submit()

    saved = Repo.get!(Page, page.id).brief
    assert saved.business_name == "Firma Testowa"
    assert saved.phone == "+48 500 000 001"
    assert saved.email == email
  end

  test "saving the brief is the one action in both Modes, and nothing offers to download or publish", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    new_idea_page = insert(:page, run: brief_run(scope))

    existing_site_page =
      insert(:page, run: brief_run(scope, %{mode: :existing_site, domain: "kancelaria-testowa.example"}))

    for page <- [new_idea_page, existing_site_page] do
      {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

      assert has_element?(view, "#page-actions > :first-child#save-brief[data-variant=lime]", "Save brief")
      refute has_element?(view, "#page-actions a")
      refute has_element?(view, "#page-actions", "Publish")
    end
  end

  test "while Step 8 writes the Brief the screen says so and turns into the editor when it's done", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-writing")
    assert has_element?(view, "#page-status-line", "I'm writing the brief.")
    refute has_element?(view, "#brief-form")

    {:ok, _page} = Pages.store_brief(page, %{"h1" => "Nagłówek z kroku 8", "sections" => [%{"question" => "Pytanie?"}]})

    refute has_element?(view, "#page-writing")
    assert has_element?(view, "#brief-form #brief-h1[value='Nagłówek z kroku 8']")
  end

  test "a failed Brief shows its error and can be started again", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :failed) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :failed, steps: steps)
    niche = insert(:niche, run: run, status: :chosen)

    page =
      insert(:page, run: run, niche: niche, status: :failed, brief: nil, error: "The model returned an invalid brief")

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-error", "The model returned an invalid brief")
    assert has_element?(view, "#page-status-line", "The brief failed: The model returned an invalid brief.")

    view |> element("#retry-brief") |> render_click()

    assert Repo.get!(Page, page.id).status == :writing
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    assert has_element?(view, "#page-writing")
  end

  test "a failed Brief on a stopped run offers to resume the research instead of retrying", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :failed) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :stopped, steps: steps)
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :failed, brief: nil, error: "Błąd testowy")
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-failed #page-run-stopped")
    assert has_element?(view, "#page-resume-link[href='/app/runs/#{run.id}']")
    assert has_element?(view, "#page-status-line", "The brief failed: Błąd testowy.")
    refute has_element?(view, "#retry-brief")

    render_hook(view, "retry_brief", %{})

    assert Repo.get!(Page, page.id) == stored
    refute_enqueued(worker: WriteBrief)
  end

  test "a Brief waiting on a stopped run offers to resume the research instead of promising the editor",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :stopped, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-run-stopped")
    assert has_element?(view, "#page-resume-link[href='/app/runs/#{run.id}']")
    assert has_element?(view, "#page-status-line", "The research is stopped, so the brief is waiting.")
    refute has_element?(view, "#page-writing")
  end

  test "stopping and resuming the research elsewhere updates the waiting Brief live", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    assert has_element?(view, "#page-writing")

    {:ok, _stopped_run} = Research.stop_run(scope, run.id)

    assert has_element?(view, "#page-run-stopped")
    assert has_element?(view, "#page-status-line", "The research is stopped, so the brief is waiting.")
    refute has_element?(view, "#page-writing")

    {:ok, _resumed_run} = Research.resume_run(scope, run.id)

    assert has_element?(view, "#page-writing")
    assert has_element?(view, "#page-status-line", "I'm writing the brief.")
    refute has_element?(view, "#page-run-stopped")
  end

  test "a crafted retry of a ready page starts nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    render_hook(view, "retry_brief", %{})

    assert Repo.get!(Page, page.id) == stored
    refute_enqueued(worker: WriteBrief)
  end

  test "a crafted save can't change the page's account or status", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    stored = Repo.get!(Page, page.id)
    other_account = insert(:account)

    forged = %{
      "account_id" => other_account.id,
      "status" => "failed"
    }

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    view
    |> form("#brief-form", brief: %{h1: "Nagłówek po próbie"})
    |> render_submit(Map.put(forged, "brief", forged))

    saved = Repo.get!(Page, page.id)
    assert saved.brief.h1 == "Nagłówek po próbie"
    assert saved.account_id == stored.account_id
    assert saved.status == stored.status
  end

  test "a crafted save of a Brief still being written changes nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    render_hook(view, "save", %{"brief" => %{"h1" => "Wpisany w trakcie", "sections" => [%{"question" => "Pytanie?"}]}})

    assert Repo.get!(Page, page.id) == stored
    assert has_element?(view, "#flash-error", "This page can't be edited now.")
  end

  test "hostile text in a Brief field stays text in the form", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    hostile = ~s|"><script>alert("x")</script><img src=x onerror=alert(1)>|
    page = insert(:page, run: brief_run(scope), brief: build(:brief, h1: hostile))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    [h1_value] = view |> element("#brief-h1") |> render() |> LazyHTML.from_fragment() |> LazyHTML.attribute("value")

    assert h1_value == hostile
    refute has_element?(view, "#page-screen script")
    refute has_element?(view, "#page-screen img")
  end

  test "another Account's page sends the User back to the pages list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(%{account: insert(:account)}))

    assert {:error, {:live_redirect, %{to: "/app/pages", flash: flash}}} = live(conn, ~p"/app/pages/#{page}")
    assert flash["error"] == "Page not found"
  end

  test "a malformed page id sends the User back to the pages list", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/pages"}}} = live(conn, "/app/pages/nie-liczba")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    page = insert(:page, run: brief_run(%{account: insert(:account)}))

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/pages/#{page}")
  end

  test "an update arriving while there are unsaved edits keeps the edits in the form", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{h1: "Nagłówek w trakcie edycji"}) |> render_change()

    Pages.broadcast_page_updated(page)

    assert has_element?(view, "#brief-h1[value='Nagłówek w trakcie edycji']")
    assert has_element?(view, "#brief-save-state", "Unsaved changes")
  end

  test "saving a Brief whose page was deleted meanwhile goes back to the pages list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    Repo.delete!(page)

    view
    |> form("#brief-form", brief: %{h1: "Nagłówek bez strony"})
    |> put_submitter("#save-brief")
    |> render_submit()

    assert {"/app/pages", %{"error" => "Page not found"}} = assert_redirect(view)
  end

  test "an update for a page deleted meanwhile goes back to the pages list", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    Repo.delete!(page)

    Pages.broadcast_page_updated(page)

    assert {"/app/pages", %{"error" => "Page not found"}} = assert_redirect(view)
  end

  test "retrying a failed Brief while another Brief is being written says why", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = brief_run(scope, %{steps: build_run_steps(Map.new(1..7, &{&1, :done}))})
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :failed, brief: nil, error: "Błąd testowy")
    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    writing_niche = insert(:niche, run: run, status: :chosen)
    insert(:page, run: run, niche: writing_niche, status: :writing, brief: nil)

    view |> element("#retry-brief") |> render_click()

    assert has_element?(view, "#flash-error", "I'm still writing the brief for another topic")
    assert Repo.get!(Page, page.id).status == :failed
    refute_enqueued(worker: WriteBrief)
  end

  defp brief_run(%{account: account}, attrs \\ %{}) do
    steps = build_run_steps(Map.new(1..8, &{&1, :done}))
    insert(:run, Map.merge(%{account: account, status: :awaiting_choice, steps: steps}, attrs))
  end
end
