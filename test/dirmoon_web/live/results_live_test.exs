defmodule DirmoonWeb.ResultsLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Page
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.WriteBrief

  @no_break_space <<0xC2, 0xA0>>

  test "the headline counts the Niches on offer and those worth going after", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)

    for score <- ["7.3", "5.1", "4.0", "3.9", "3.2", "2.6", "2.1", "1.4", "0.8"] do
      insert(:niche, run: run, score: Decimal.new(score))
    end

    insert(:niche, run: run, score: Decimal.new("9.9"), status: :rejected)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#results-headline", "Dziewięć nisz.")
    assert has_element?(view, "#results-headline [data-part=underline]", "Trzy warte zajęcia.")
  end

  test "the Niches are listed by Score with Score, monthly Volume and a competition verdict", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    second = insert(:niche, run: run, score: Decimal.new("5.2"), name: "Nisza druga testowa")
    first = insert(:niche, run: run, score: Decimal.new("6.7"), name: "Nisza pierwsza testowa")
    checked = phrase_in_niche(run, first, %{volume: 1_234, cpc: "0.31"})
    phrase_in_niche(run, second, %{volume: 57, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"forum" => 6, "blog" => 4}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niches li:nth-child(2)#niche-row-#{first.id}")
    assert has_element?(view, "#niche-row-#{first.id}", "szansa 7/10 · 1#{@no_break_space}234 / mies.")
    assert has_element?(view, "#niche-row-#{first.id} .text-accent", "Słaba konkurencja: fora, blogi")
    assert has_element?(view, "#niche-row-#{second.id}", "szansa 5/10 · 57 / mies.")
    assert has_element?(view, "#niche-row-#{second.id}", "Konkurencja niesprawdzona")
  end

  test "strong competition shows in the warning colour", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("4.4"))
    checked = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 7, "portal" => 3}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-row-#{niche.id} .text-warn", "Mocna konkurencja: konkurenci, portale")
  end

  test "Niches scoring under 4 are collapsed behind one row that expands on click", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    worth = insert(:niche, run: run, score: Decimal.new("4.6"))
    low = Enum.map(["3.1", "1.7"], &insert(:niche, run: run, score: Decimal.new(&1)))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-row-#{worth.id}")
    assert has_element?(view, "#collapsed-niches", "+ 2 nisze z oceną poniżej 4")

    for niche <- low do
      refute has_element?(view, "#niche-row-#{niche.id}")
    end

    view |> element("#collapsed-niches") |> render_click()

    for niche <- low do
      assert has_element?(view, "#niche-row-#{niche.id}")
    end

    refute has_element?(view, "#collapsed-niches")
  end

  test "the selected Niche shows its title, reading, three stat tiles and its Phrases", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{city: "Płock", city_location_code: 9_990_777})

    niche =
      insert(:niche,
        run: run,
        score: Decimal.new("6.4"),
        name: "Czartery testowe",
        reading: "Pierwsze zdanie testowe. Drugie zdanie testowe."
      )

    checked = phrase_in_niche(run, niche, %{volume: 2_345, cpc: "0.40"})
    insert(:volume, phrase: checked.phrase, location_code: 9_990_777, search_volume: 13)
    unchecked = phrase_in_niche(run, niche, %{volume: 655, cpc: "1.20"})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"blog" => 5, "directory" => 5}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail", "nisza · 2 frazy · szansa 6/10")
    assert has_element?(view, "#niche-detail h2", "Czartery testowe")
    assert has_element?(view, "#niche-detail", "Pierwsze zdanie testowe. Drugie zdanie testowe.")
    assert has_element?(view, "#niche-stats #niche-stat-volume", "3#{@no_break_space}000")
    assert has_element?(view, "#niche-stats #niche-stat-cpc", "$0,57")
    assert has_element?(view, "#niche-stats #niche-stat-competitors", "0")
    assert has_element?(view, "#niche-detail th", "Polska")
    assert has_element?(view, "#niche-phrases-city", "Płock")
    assert has_element?(view, "#niche-phrases-#{checked.id}", checked.phrase.phrase)
    assert has_element?(view, "#niche-phrases-#{checked.id}", "2#{@no_break_space}345")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "13")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "$0,40")
    assert has_element?(view, "#niche-phrases-#{checked.id}", "blogi, katalogi")
    assert has_element?(view, "#niche-phrases-#{unchecked.id}", "—")
  end

  test "a run without a city has no city column", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))
    phrase_in_niche(run, niche, %{volume: 30, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail")
    refute has_element?(view, "#niche-phrases-city")
  end

  test "a New Idea run's third tile counts direct competitors in the top 10", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    checked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"direct_competitor" => 3, "blog" => 7}))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-stat-competitors", "Konkurenci w top 10 (maks.)")
    assert has_element?(view, "#niche-stat-competitors [data-part=value]", "3")
    refute has_element?(view, "#niche-stat-position")
    refute has_element?(view, "#niche-phrases-position")
  end

  test "an Existing Site run's third tile and last column show the site's Current Positions", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{mode: :existing_site, domain: "strona-testowa.pl"})
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    ranked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    ranked |> Ecto.Changeset.change(current_position: Decimal.new("13.7")) |> Repo.update!()
    phrase_in_niche(run, niche, %{volume: 10, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-stat-position", "Najlepsza obecna pozycja")
    assert has_element?(view, "#niche-stat-position [data-part=value]", "13,7")
    assert has_element?(view, "#niche-phrases-position", "Pozycja")
    assert has_element?(view, "#niche-phrases-#{ranked.id}", "13,7")
    refute has_element?(view, "#niche-stat-competitors")
    assert has_element?(view, "#run-parameters", "strona-testowa.pl")
  end

  test "all the Niche's Phrases show after clicking the button that names their count", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.5"))
    phrases = Enum.map(1..12, &phrase_in_niche(run, niche, %{volume: 100 - &1, cpc: nil}))
    last = List.last(phrases)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    refute has_element?(view, "#niche-phrases-#{last.id}")

    view |> element("#all-phrases", "Wszystkie 12 fraz") |> render_click()

    assert has_element?(view, "#niche-phrases-#{last.id}")
    refute has_element?(view, "#all-phrases")
  end

  test "clicking a Niche's row selects it", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("7.0"))
    other = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza do kliknięcia")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#niche-row-#{other.id} a") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{other.id}&view=niches")
    assert has_element?(view, "#niche-detail h2", "Nisza do kliknięcia")
    assert has_element?(view, "#niche-row-#{other.id} a[data-selected]")
  end

  test "\"Wszystkie frazy\" lists the kept Phrases with their Niche, Volume and CPC", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza widoku fraz")
    kept = phrase_in_niche(run, niche, %{volume: 4_321, cpc: "0.65"})
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą testową")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#view-phrases") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{niche.id}&view=phrases")
    assert has_element?(view, "#view-phrases[aria-current=page] [data-part=count]", "1")
    assert has_element?(view, "#view-rejected [data-part=count]", "1")
    assert has_element?(view, "#view-niches [data-part=count]", "1")
    assert has_element?(view, "#phrases-#{kept.id}", kept.phrase.phrase)
    assert has_element?(view, "#phrases-#{kept.id}", "Nisza widoku fraz")
    assert has_element?(view, "#phrases-#{kept.id}", "4#{@no_break_space}321 / mies. · CPC $0,65")
    refute has_element?(view, "#phrases-#{rejected.id}")
    refute has_element?(view, "#niches")
  end

  test "\"Odrzucone\" lists the Rejected Phrases with their reasons", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("5.0"))
    rejected = insert(:run_phrase, run: run, status: :rejected, rejection_reason: "poza ofertą testową")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=rejected")

    assert has_element?(view, "#view-rejected[aria-current=page]", "Odrzucone")
    assert has_element?(view, "#rejected-phrases-#{rejected.id}", rejected.phrase.phrase)
    assert has_element?(view, "#rejected-phrases-#{rejected.id}", "poza ofertą testową")
  end

  test "an unknown view falls back to the Niches", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=cokolwiek")

    assert has_element?(view, "#niche-row-#{niche.id}")
    assert has_element?(view, "#view-niches[aria-current=page]")
  end

  test "another run's Niche in the URL is ignored and the top Niche is selected", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    top = insert(:niche, run: run, score: Decimal.new("6.0"), name: "Nisza najlepsza testowa")
    foreign = insert(:niche, run: scored_run(scope), score: Decimal.new("9.0"), name: "Nisza z innego researchu")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{foreign.id}")

    assert has_element?(view, "#niche-detail[data-niche-id='#{top.id}']", "Nisza najlepsza testowa")
    refute has_element?(view, "#results", "Nisza z innego researchu")
  end

  test "a malformed Niche id in the URL selects the top Niche", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    top = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=nie-liczba")

    assert has_element?(view, "#niche-detail[data-niche-id='#{top.id}']")
  end

  test "choosing the Niche starts Step 8 and opens the page screen", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#choose-niche", "Wybierz niszę i napisz stronę") |> render_click()

    page = Repo.get_by!(Page, cluster_id: niche.id)
    assert_redirect(view, "/app/pages/#{page.id}")
    assert page.status == :writing
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "a choice that can't start says why", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    writing = insert(:niche, run: run, score: Decimal.new("5.0"), status: :chosen)
    insert(:page, run: run, niche: writing, status: :writing, brief: nil)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "Brief dla innej niszy jest w trakcie pisania")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "a stopped run hides the choice and points to the run screen to resume it", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{status: :stopped})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#niche-detail[data-niche-id='#{niche.id}']")
    assert has_element?(view, "#results-run-stopped", "Research jest zatrzymany. Wznów go, żeby wybrać niszę.")
    assert has_element?(view, "#results-resume-link[href='/app/runs/#{run.id}']")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
  end

  test "a choice on a stopped run sent anyway changes nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope, %{status: :stopped})
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    render_hook(view, "choose", %{})
    render_hook(view, "reject", %{})

    assert Repo.get!(Niche, niche.id).status == :proposed
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "a choice the run is too busy for says the research is still working", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    steps = 1..8 |> Map.new(&{&1, :done}) |> Map.put(9, :running) |> build_run_steps()
    run = insert(:run, account: scope.account, status: :running, steps: steps)
    published = insert(:niche, run: run, score: Decimal.new("5.0"), status: :chosen)
    insert(:page, run: run, niche: published, status: :publishing)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "Research jeszcze pracuje")
    assert Repo.get_by(Page, cluster_id: niche.id) == nil
    refute_enqueued(worker: WriteBrief)
  end

  test "crafted choose and reject events before Step 7 change nothing", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = 1..4 |> Map.new(&{&1, :done}) |> Map.put(5, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run)
    other_run_niche = insert(:niche, run: scored_run(scope))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    render_hook(view, "choose", %{"niche_id" => other_run_niche.id})
    render_hook(view, "reject", %{"niche_id" => other_run_niche.id})

    for untouched <- [niche, other_run_niche] do
      assert Repo.get!(Niche, untouched.id).status == :proposed
    end

    assert Repo.all(Page) == []
    refute_enqueued(worker: WriteBrief)
  end

  test "a crafted Niche id is ignored and the selected Niche is the one chosen", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    selected = insert(:niche, run: run, score: Decimal.new("6.0"))
    foreign = insert(:niche, run: scored_run(%{account: insert(:account)}), score: Decimal.new("7.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{selected.id}")
    render_hook(view, "choose", %{"niche_id" => foreign.id})

    page = Repo.get_by!(Page, cluster_id: selected.id)
    assert_redirect(view, "/app/pages/#{page.id}")
    assert Repo.get!(Niche, foreign.id).status == :proposed
    assert Repo.get_by(Page, cluster_id: foreign.id) == nil
  end

  test "a crafted Niche id on reject is ignored and the selected Niche is the one rejected", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    selected = insert(:niche, run: run, score: Decimal.new("6.0"))
    foreign = insert(:niche, run: scored_run(%{account: insert(:account)}), score: Decimal.new("7.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{selected.id}")
    render_hook(view, "reject", %{"niche_id" => foreign.id})

    assert Repo.get!(Niche, selected.id).status == :rejected
    assert Repo.get!(Niche, foreign.id).status == :proposed
  end

  test "a Niche that already has a page links to it instead of offering a choice", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"), status: :chosen)
    page = insert(:page, run: run, niche: niche)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "#open-page[href='/app/pages/#{page.id}']", "Otwórz stronę")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
  end

  test "rejecting the Niche takes it off the list, updates the counts and selects the next one", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    rejected = insert(:niche, run: run, score: Decimal.new("6.0"))
    next = insert(:niche, run: run, score: Decimal.new("5.0"), name: "Nisza następna testowa")

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#reject-niche", "Odrzuć niszę") |> render_click()

    assert_patch(view, "/app/runs/#{run.id}/results?niche=#{next.id}&view=niches")
    assert Repo.get!(Niche, rejected.id).status == :rejected
    refute has_element?(view, "#niche-row-#{rejected.id}")
    assert has_element?(view, "#view-niches [data-part=count]", "1")
    assert has_element?(view, "#results-headline", "Jedna nisza.")
    assert has_element?(view, "#niche-detail h2", "Nisza następna testowa")
  end

  test "rejecting the last Niche leaves an empty list", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    view |> element("#reject-niche") |> render_click()

    assert has_element?(view, "#results-headline", "Zero nisz.")
    assert has_element?(view, "#niche-detail-empty")
    refute has_element?(view, "#choose-niche")
  end

  test "the CSV export is a real link to the run's export", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = scored_run(scope)

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")

    assert has_element?(view, "a#export-csv[href='/app/runs/#{run.id}/export.csv']", "Eksport CSV")
  end

  test "before Step 7 has finished the Phrases so far show without a Niche choice", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = 1..4 |> Map.new(&{&1, :done}) |> Map.put(5, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, %{volume: 80, cpc: nil})

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?view=niches")

    assert has_element?(view, "#results-headline", "Frazy do tej pory.")
    assert has_element?(view, "#phrases-#{kept.id}", kept.phrase.phrase)
    assert has_element?(view, "#view-niches[aria-disabled] [data-part=count]", "1")
    assert has_element?(view, "#back-to-run[href='/app/runs/#{run.id}']")
    refute has_element?(view, "#choose-niche")
    refute has_element?(view, "#reject-niche")
    refute has_element?(view, "#niche-detail")
  end

  test "the results fill in when Step 7 finishes while the screen is open", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    statuses = 1..6 |> Map.new(&{&1, :done}) |> Map.put(7, :running)
    run = insert(:run, account: scope.account, status: :running, steps: build_run_steps(statuses))
    niche = insert(:niche, run: run, score: Decimal.new("5.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results")
    refute has_element?(view, "#choose-niche")

    RunStep
    |> Repo.get_by!(run_id: run.id, number: 7)
    |> Ecto.Changeset.change(status: :done)
    |> Repo.update!()

    Research.broadcast_run_updated(run)

    assert has_element?(view, "#niche-row-#{niche.id}")
    assert has_element?(view, "#choose-niche")
    assert has_element?(view, "#results-headline", "Jedna nisza.")
  end

  test "another Account's run sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    run = scored_run(%{account: insert(:account)})

    assert {:error, {:live_redirect, %{to: "/app/runs", flash: flash}}} = live(conn, ~p"/app/runs/#{run}/results")
    assert flash["error"] == "Nie znaleziono researchu"
  end

  test "a malformed run id sends the User back to the runs list", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/app/runs"}}} = live(conn, "/app/runs/nie-liczba/results")
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    run = scored_run(%{account: insert(:account)})

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app/runs/#{run}/results")
  end

  defp scored_run(%{account: account}, attrs \\ %{}) do
    steps = build_run_steps(Map.new(1..7, &{&1, :done}))
    insert(:run, Map.merge(%{account: account, status: :awaiting_choice, steps: steps}, attrs))
  end

  defp phrase_in_niche(run, niche, metrics) do
    phrase = insert(:phrase, phrase: unique_phrase_text("fraza wyników"))

    insert(:volume,
      phrase: phrase,
      location_code: run.location_code,
      search_volume: metrics.volume,
      cpc: metrics.cpc && Decimal.new(metrics.cpc)
    )

    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
  end

  defp labels(counts_by_page_type) do
    counts_by_page_type
    |> Enum.flat_map(fn {page_type, count} -> List.duplicate(page_type, count) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {page_type, position} -> %{"position" => position, "page_type" => page_type} end)
  end
end
