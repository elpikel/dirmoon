defmodule DirmoonWeb.PageLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Pages
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Workers.PublishPage
  alias Dirmoon.Workers.WriteBrief

  test "the Brief form shows on the left and the rendered page in a browser frame on the right", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = brief_run(scope)
    page = insert(:page, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#brief-form #brief-title")
    assert has_element?(view, "#brief-form #brief-slug")
    assert has_element?(view, "#brief-sections #brief-section-0")
    assert has_element?(view, "iframe#page-preview[sandbox=''][title='Podgląd strony']")
    assert has_element?(view, "#preview-address", "[TWOJA-DOMENA]/#{page.brief.slug}")
    assert preview_text(view, "h1") == page.brief.h1
  end

  test "the hero names the Niche and says the Brief and the page are ready", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-context", "Nisza: #{page.niche.name}")
    assert has_element?(view, "#page-headline", "Brief gotowy.")
    assert has_element?(view, "#page-headline [data-part=underline]", "Strona też.")
  end

  test "the status line counts the Brief's questions and leaves prices and contact data to the User", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Pierwsze?"}, %Brief.Section{question: "Drugie?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(
             view,
             "#page-status-line",
             "Ułożyłem stronę z 2 pytań klientów. Ceny i dane kontaktowe uzupełniasz Ty."
           )

    refute has_element?(view, "#page-status-line", "zatwierdzić")
  end

  test "an Existing Site page's status line says legal, medical or financial answers need the owner's approval",
       %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope, %{mode: :existing_site, domain: "kancelaria-testowa.example"}))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(
             view,
             "#page-status-line",
             "Odpowiedzi prawne, medyczne i finansowe musi zatwierdzić właściciel firmy przed publikacją."
           )
  end

  test "typing in the H1 updates the preview without saving", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{h1: "Nowy nagłówek podglądu"}) |> render_change()

    assert preview_text(view, "h1") == "Nowy nagłówek podglądu"
    assert has_element?(view, "#brief-save-state", "Niezapisane zmiany")
    assert Repo.get!(Page, page.id).brief.h1 == page.brief.h1
  end

  test "saving the Brief persists the edit", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    view
    |> form("#brief-form", brief: %{h1: "Zapisany nagłówek", slug: "zapisany-adres"})
    |> put_submitter("#save-brief")
    |> render_submit()

    saved = Repo.get!(Page, page.id)
    assert saved.brief.h1 == "Zapisany nagłówek"
    assert saved.brief.slug == "zapisany-adres"
    assert has_element?(view, "#brief-save-state", "Zapisano")
    assert has_element?(view, "#preview-address", "[TWOJA-DOMENA]/zapisany-adres")
    assert preview_text(view, "h1") == "Zapisany nagłówek"
  end

  test "an invalid field shows its error and saves nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{slug: "Zły Adres!", h1: "Nagłówek, który nie przejdzie"}) |> render_submit()

    assert has_element?(view, "label[for=brief-slug] + p", "ma nieprawidłowy format")
    assert has_element?(view, "#flash-error", "Popraw zaznaczone pola briefu.")
    assert Repo.get!(Page, page.id).brief == page.brief
  end

  test "a section can be added and the new question saved", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
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
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Zostaje?"}, %Brief.Section{question: "Do usunięcia?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_change(%{"brief" => %{"sections_drop" => ["1"]}})

    refute has_element?(view, "#brief-section-1")
    assert preview_texts(view, "h2[id^=sekcja-]") == ["Zostaje?"]

    view |> form("#brief-form") |> render_submit()

    assert [%Brief.Section{question: "Zostaje?"}] = Repo.get!(Page, page.id).brief.sections
  end

  test "a section can be moved up", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    sections = [%Brief.Section{question: "Pierwsze?"}, %Brief.Section{question: "Drugie?"}]
    page = insert(:page, run: brief_run(scope), brief: build(:brief, sections: sections))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_change(%{"brief" => %{"sections_move_up" => ["1"]}})

    assert has_element?(view, "#brief-section-0 input[name='brief[sections][0][question]'][value='Drugie?']")
    assert preview_texts(view, "h2[id^=sekcja-]") == ["Drugie?", "Pierwsze?"]
  end

  test "dropping every section shows that the Brief needs one", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form") |> render_submit(%{"brief" => %{"sections_drop" => ["0"]}})

    assert has_element?(view, "#brief-sections-error", "powinno mieć co najmniej 1 element")
    assert Repo.get!(Page, page.id).brief.sections == page.brief.sections
  end

  test "the Phrases to cover show as chips with the primary one marked", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    brief = build(:brief, phrases: ["fraza poboczna", "fraza główna"], primary_phrase: "fraza główna")
    page = insert(:page, run: brief_run(scope), brief: brief)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#brief-phrases li:first-child[data-primary]", "fraza główna")
    assert has_element?(view, "#brief-phrases li:not([data-primary])", "fraza poboczna")
  end

  test "the business details are editable in a collapsible group", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    assert has_element?(view, "#brief-business.hidden")

    view |> element("#toggle-business") |> render_click()
    refute has_element?(view, "#brief-business.hidden")

    view
    |> form("#brief-form", brief: %{business_name: "Firma Testowa", nav_links: ["Oferta", "", ""]})
    |> render_submit()

    saved = Repo.get!(Page, page.id).brief
    assert saved.business_name == "Firma Testowa"
    assert saved.nav_links == ["Oferta"]
  end

  test "a New Idea page's primary action publishes to Netlify and the secondary downloads the Content File",
       %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-actions > :first-child#publish-page[data-variant=lime]", "Opublikuj na Netlify")
    assert has_element?(view, "#download-page[data-variant=outline]", "Pobierz plik treści")
  end

  test "an Existing Site page's primary action downloads the Content File", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope, %{mode: :existing_site, domain: "kancelaria-testowa.example"}))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-actions > :first-child#download-page[data-variant=lime]", "Pobierz plik treści")
    assert has_element?(view, "#publish-page[data-variant=outline]", "Opublikuj na Netlify")
  end

  test "the download link points at the page's Content File", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "a#download-page[href='/app/pages/#{page.id}/file']")
  end

  test "publishing enqueues Step 9 and the button says it is publishing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = brief_run(scope)
    page = insert(:page, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> element("#publish-page") |> render_click()

    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
    assert Repo.get!(Page, page.id).status == :publishing
    assert has_element?(view, "#publish-page[disabled]", "Publikuję…")
    assert has_element?(view, "#page-headline", "Publikuję")
  end

  test "publishing saves pending edits first", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = brief_run(scope)
    page = insert(:page, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{h1: "Nagłówek przed publikacją"}) |> render_change()
    view |> element("#publish-page") |> render_click()

    published = Repo.get!(Page, page.id)
    assert published.brief.h1 == "Nagłówek przed publikacją"
    assert published.status == :publishing
    assert_enqueued(worker: PublishPage, args: %{run_id: run.id})
  end

  test "publishing with invalid pending edits publishes nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> form("#brief-form", brief: %{h1: ""}) |> render_change()
    view |> element("#publish-page") |> render_click()

    assert has_element?(view, "label[for=brief-h1] + p", "nie może być puste")
    assert Repo.get!(Page, page.id).status == :ready
    refute_enqueued(worker: PublishPage)
  end

  test "publishing while the research is busy says so", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> element("#publish-page") |> render_click()

    assert has_element?(view, "#flash-error", "Research jeszcze pracuje")
    assert Repo.get!(Page, page.id).status == :ready
    refute_enqueued(worker: PublishPage)
  end

  test "publishing a page whose stored Brief is incomplete says it can't be published", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope), brief: build(:brief, h1: nil))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    view |> element("#publish-page") |> render_click()

    assert has_element?(view, "#flash-error", "Tej strony nie można teraz opublikować")
    refute_enqueued(worker: PublishPage)
  end

  test "a published page shows its URL as a link", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    brief = build(:brief)
    url = "https://#{brief.slug}.example"
    page = insert(:page, run: brief_run(scope), brief: brief, status: :published, published_url: url)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "a#published-url[href='#{url}'][target=_blank][rel=noopener]", url)
    assert has_element?(view, "#preview-address", url)
  end

  test "a failed publish shows its error", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope), error: "Netlify: nieprawidłowy token")

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#publish-error", "Netlify: nieprawidłowy token")
  end

  test "while Step 8 writes the Brief the screen says so and turns into the editor when it's done", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-writing")
    assert has_element?(view, "#page-headline", "Piszę")
    refute has_element?(view, "#brief-form")

    {:ok, _page} = Pages.store_brief(page, %{"h1" => "Nagłówek z kroku 8", "sections" => [%{"question" => "Pytanie?"}]})

    refute has_element?(view, "#page-writing")
    assert has_element?(view, "#brief-form")
    assert preview_text(view, "h1") == "Nagłówek z kroku 8"
  end

  test "a failed Brief shows its error and can be started again", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :failed) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :failed, steps: steps)
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :failed, brief: nil, error: "Model zwrócił niepoprawny brief")

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-error", "Model zwrócił niepoprawny brief")
    assert has_element?(view, "#page-headline", "nie udał.")

    view |> element("#retry-brief") |> render_click()

    assert Repo.get!(Page, page.id).status == :writing
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
    assert has_element?(view, "#page-writing")
  end

  test "a failed Brief on a stopped run offers to resume the research instead of retrying", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :failed) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :stopped, steps: steps)
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :failed, brief: nil, error: "Błąd testowy")
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-failed #page-run-stopped")
    assert has_element?(view, "#page-resume-link[href='/app/runs/#{run.id}']")
    assert has_element?(view, "#page-headline [data-part=underline]", "nie udał.")
    refute has_element?(view, "#retry-brief")

    render_hook(view, "retry_brief", %{})

    assert Repo.get!(Page, page.id) == stored
    refute_enqueued(worker: WriteBrief)
  end

  test "a Brief waiting on a stopped run offers to resume the research instead of promising the editor",
       %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :stopped, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-run-stopped")
    assert has_element?(view, "#page-resume-link[href='/app/runs/#{run.id}']")
    assert has_element?(view, "#page-status-line", "Research jest zatrzymany, więc brief czeka.")
    assert has_element?(view, "#page-headline", "Brief")
    assert has_element?(view, "#page-headline [data-part=underline]", "czeka.")
    refute has_element?(view, "#page-headline", "Piszę")
    refute has_element?(view, "#page-writing")
  end

  test "stopping and resuming the research elsewhere updates the waiting Brief live", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    assert has_element?(view, "#page-writing")

    {:ok, _stopped_run} = Research.stop_run(scope, run.id)

    assert has_element?(view, "#page-run-stopped")
    assert has_element?(view, "#page-headline [data-part=underline]", "czeka.")
    refute has_element?(view, "#page-writing")

    {:ok, _resumed_run} = Research.resume_run(scope, run.id)

    assert has_element?(view, "#page-writing")
    assert has_element?(view, "#page-headline [data-part=underline]", "brief.")
    refute has_element?(view, "#page-run-stopped")
  end

  test "a page publishing on a stopped run offers to resume the research", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..8 |> Map.new(&{&1, :done}) |> Map.put(9, :queued) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :stopped, steps: steps)
    page = insert(:page, run: run, status: :publishing)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    assert has_element?(view, "#page-run-stopped")
    assert has_element?(view, "#page-resume-link[href='/app/runs/#{run.id}']")
    assert has_element?(view, "#page-status-line", "Research jest zatrzymany, więc publikacja czeka.")
    assert has_element?(view, "#page-headline", "Publikacja")
    assert has_element?(view, "#page-headline [data-part=underline]", "czeka.")
    refute has_element?(view, "#page-headline", "Publikuję")
  end

  test "a crafted retry of a ready page starts nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    render_hook(view, "retry_brief", %{})

    assert Repo.get!(Page, page.id) == stored
    refute_enqueued(worker: WriteBrief)
  end

  test "a crafted save can't change the page's account, status, URL or hosting site", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(scope))
    stored = Repo.get!(Page, page.id)
    other_account = insert(:account)

    forged = %{
      "account_id" => other_account.id,
      "status" => "published",
      "published_url" => "https://podrobiona.example",
      "hosting_site_id" => "podrobiona-witryna"
    }

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")

    view
    |> form("#brief-form", brief: %{h1: "Nagłówek po próbie"})
    |> render_submit(Map.put(forged, "brief", forged))

    saved = Repo.get!(Page, page.id)
    assert saved.brief.h1 == "Nagłówek po próbie"
    assert saved.account_id == stored.account_id
    assert saved.status == stored.status
    assert saved.published_url == stored.published_url
    assert saved.hosting_site_id == stored.hosting_site_id
  end

  test "a crafted publish while the page is publishing enqueues no second job", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = brief_run(scope)
    page = insert(:page, run: run)
    {:ok, _publishing_page} = Pages.publish(scope, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    render_hook(view, "publish", %{})

    assert [_only_job] = all_enqueued(worker: PublishPage, args: %{run_id: run.id})
    assert Repo.get!(Page, page.id).status == :publishing
  end

  test "a crafted save of a Brief still being written changes nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    page = insert(:page, run: run, status: :writing, brief: nil)
    stored = Repo.get!(Page, page.id)

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    render_hook(view, "save", %{"brief" => %{"h1" => "Wpisany w trakcie", "sections" => [%{"question" => "Pytanie?"}]}})

    assert Repo.get!(Page, page.id) == stored
  end

  test "hostile text in a Brief field stays text inside the preview", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    hostile = ~s|"></iframe><script>alert("x")</script><img src=x onerror=alert(1)>|
    page = insert(:page, run: brief_run(scope), brief: build(:brief, h1: hostile))

    {:ok, view, _html} = live(conn, ~p"/app/pages/#{page}")
    document = preview_document(view)

    assert has_element?(view, "iframe#page-preview")
    refute has_element?(view, "script", "alert")
    assert document |> LazyHTML.query("h1") |> LazyHTML.text() == hostile
    assert document |> LazyHTML.query("script") |> Enum.to_list() == []
    assert document |> LazyHTML.query("img") |> Enum.to_list() == []
  end

  test "another Account's page sends the User back to the pages list", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: brief_run(%{account: insert(:account)}))

    assert {:error, {:live_redirect, %{to: "/app/pages", flash: flash}}} = live(conn, ~p"/app/pages/#{page}")
    assert flash["error"] == "Nie znaleziono strony"
  end

  test "a malformed page id sends the User back to the pages list", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/pages"}}} = live(conn, "/app/pages/nie-liczba")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    page = insert(:page, run: brief_run(%{account: insert(:account)}))

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/pages/#{page}")
  end

  defp brief_run(%{account: account}, attrs \\ %{}) do
    steps = build_run_steps(Map.new(1..8, &{&1, :done}))
    insert(:run, Map.merge(%{account: account, status: :awaiting_choice, steps: steps}, attrs))
  end

  defp preview_document(view) do
    [srcdoc] =
      view
      |> element("#page-preview")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("srcdoc")

    LazyHTML.from_document(srcdoc)
  end

  defp preview_text(view, selector) do
    view
    |> preview_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end

  defp preview_texts(view, selector) do
    view
    |> preview_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end
end
