defmodule Dirmoon.NichesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Workers.WriteBrief

  test "storing a grouping creates the niches in order, assigns their phrases and rejects the rest" do
    run = insert(:run)
    [grouped, dropped, left_out] = insert_list(3, :run_phrase, run: run)

    assert {:ok, %{niches: 1, kept: 1, rejected: 2}} =
             Niches.store_grouping(run, %{
               niches: [%{name: "Hotel dla psa", intent: "lokalna", reading: "Zdanie. Zdanie.", phrase_ids: [grouped.id]}],
               rejected: [%{phrase_id: dropped.id, reason: "inna branża"}]
             })

    assert [%Niche{id: niche_id, name: "Hotel dla psa", position: 1, status: :proposed}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert %RunPhrase{status: :kept, cluster_id: ^niche_id} = Repo.get!(RunPhrase, grouped.id)
    assert %RunPhrase{status: :rejected, rejection_reason: "inna branża"} = Repo.get!(RunPhrase, dropped.id)
    assert %RunPhrase{status: :rejected, rejection_reason: "pominięta przez model"} = Repo.get!(RunPhrase, left_out.id)
  end

  test "storing a grouping again replaces the run's niches and decisions instead of adding to them" do
    run = insert(:run)
    [first, second] = insert_list(2, :run_phrase, run: run)

    {:ok, _counts} =
      Niches.store_grouping(run, %{
        niches: [%{name: "Pierwsza", intent: nil, reading: nil, phrase_ids: [first.id]}],
        rejected: [%{phrase_id: second.id, reason: "inna branża"}]
      })

    assert {:ok, %{niches: 1, kept: 2, rejected: 0}} =
             Niches.store_grouping(run, %{
               niches: [%{name: "Druga", intent: nil, reading: nil, phrase_ids: [first.id, second.id]}],
               rejected: []
             })

    assert [%Niche{id: niche_id, name: "Druga"}] =
             Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all()

    assert %RunPhrase{status: :kept, rejection_reason: nil, cluster_id: ^niche_id} = Repo.get!(RunPhrase, second.id)
  end

  test "storing a grouping without niches creates none and rejects every phrase" do
    run = insert(:run)
    [dropped, left_out] = insert_list(2, :run_phrase, run: run)

    assert {:ok, %{niches: 0, kept: 0, rejected: 2}} =
             Niches.store_grouping(run, %{niches: [], rejected: [%{phrase_id: dropped.id, reason: "inna branża"}]})

    assert Niche |> from(as: :niche) |> where([niche: niche], niche.run_id == ^run.id) |> Repo.all() == []
    assert %RunPhrase{status: :rejected, rejection_reason: "pominięta przez model"} = Repo.get!(RunPhrase, left_out.id)
  end

  test "storing a grouping leaves other runs' niches and phrases alone" do
    run = insert(:run)
    run_phrase = insert(:run_phrase, run: run)
    other_niche = insert(:niche)
    other_run_phrase = insert(:run_phrase, run: other_niche.run, niche: other_niche)

    {:ok, _counts} =
      Niches.store_grouping(run, %{
        niches: [%{name: "Nisza", intent: nil, reading: nil, phrase_ids: [run_phrase.id]}],
        rejected: []
      })

    assert Repo.get!(Niche, other_niche.id)
    assert %RunPhrase{status: :kept, cluster_id: other_cluster_id} = Repo.get!(RunPhrase, other_run_phrase.id)
    assert other_cluster_id == other_niche.id
  end

  test "a run's niches are listed by score, unscored ones last in the model's order, with their phrase counts" do
    run = insert(:run)
    unscored_earlier = insert(:niche, run: run, position: 2)
    unscored_later = insert(:niche, run: run, position: 3)
    top = insert(:niche, run: run, position: 4, score: Decimal.new("7.50"))
    lower = insert(:niche, run: run, position: 1, score: Decimal.new("3.20"))
    insert_list(2, :run_phrase, run: run, niche: top)
    insert(:run_phrase, run: run, niche: unscored_later)
    insert(:niche)

    niches = Niches.list_for_run(run)

    assert Enum.map(niches, & &1.id) == [top.id, lower.id, unscored_earlier.id, unscored_later.id]
    assert Enum.map(niches, & &1.phrase_count) == [2, 0, 0, 1]
  end

  test "a niche's aggregates carry its kept phrases' market totals" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, %{volume: 30, cpc: "1.00"})
    phrase_in_niche(run, niche, %{volume: 10, cpc: "3.00"})

    assert [aggregate] = Niches.niche_aggregates(run)

    assert aggregate.niche_id == niche.id
    assert aggregate.volume == 40
    assert Decimal.equal?(aggregate.cpc, Decimal.new("1.5"))
  end

  test "a niche without phrases has no volume, no cpc and no weak share" do
    run = insert(:run)
    niche = insert(:niche, run: run)

    assert Niches.niche_aggregates(run) == [%{niche_id: niche.id, volume: 0, cpc: nil, weak_share: nil}]
  end

  test "a niche's weak share pools the labels of all its assessed phrases" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    all_blogs = phrase_in_niche(run, niche, %{volume: 50, cpc: nil})
    mostly_portals = phrase_in_niche(run, niche, %{volume: 40, cpc: nil})
    phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    insert(:serp_assessment, run: run, phrase: all_blogs.phrase, labels: labels(%{"blog" => 4}))
    insert(:serp_assessment, run: run, phrase: mostly_portals.phrase, labels: labels(%{"forum" => 1, "portal" => 5}))

    assert [%{weak_share: 0.5}] = Niches.niche_aggregates(run)
  end

  test "only proposed niches are aggregated, in position order" do
    run = insert(:run)
    second = insert(:niche, run: run, position: 2)
    first = insert(:niche, run: run, position: 1)
    rejected_niche = insert(:niche, run: run, status: :rejected, position: 3)
    phrase_in_niche(run, rejected_niche, %{volume: 80, cpc: "2.00"})

    assert Enum.map(Niches.niche_aggregates(run), & &1.niche_id) == [first.id, second.id]
  end

  test "rejected phrases and other runs' assessments stay out of the weak share" do
    run = insert(:run)
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, %{volume: 25, cpc: "1.00"})
    rejected = phrase_in_niche(run, niche, %{volume: 900, cpc: "9.00", status: :rejected})
    insert(:serp_assessment, run: run, phrase: rejected.phrase, labels: labels(%{"blog" => 3}))
    insert(:serp_assessment, phrase: kept.phrase, labels: labels(%{"blog" => 3}))

    assert [%{niche_id: niche_id, volume: 25, weak_share: nil}] = Niches.niche_aggregates(run)
    assert niche_id == niche.id
  end

  test "storing scores writes each niche's score and components" do
    run = insert(:run)
    [first, second] = insert_list(2, :niche, run: run)
    components = %{"volume" => 0.25, "cpc" => 0.5, "weakness" => 1.0}

    assert {:ok, 2} =
             Niches.store_scores(run, [
               %{niche_id: first.id, score: Decimal.new("6.3"), components: components},
               %{niche_id: second.id, score: Decimal.new("1.2"), components: components}
             ])

    assert %Niche{score: first_score, score_components: ^components} = Repo.get!(Niche, first.id)
    assert Decimal.equal?(first_score, Decimal.new("6.3"))
    assert Decimal.equal?(Repo.get!(Niche, second.id).score, Decimal.new("1.2"))
  end

  test "storing scores never touches another run's niches" do
    run = insert(:run)
    other_niche = insert(:niche)

    assert {:ok, 0} =
             Niches.store_scores(run, [
               %{niche_id: other_niche.id, score: Decimal.new("5.5"), components: %{"volume" => 1.0}}
             ])

    assert %Niche{score: nil, score_components: nil} = Repo.get!(Niche, other_niche.id)
  end

  test "picking a niche of a run awaiting a choice marks it chosen, creates its page and enqueues step 8" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)

    assert {:ok, %Page{status: :writing} = page} = Niches.choose(scope_for(run.account), niche.id)

    assert %Page{account_id: account_id, run_id: run_id, cluster_id: cluster_id} = Repo.get!(Page, page.id)
    assert {account_id, run_id, cluster_id} == {run.account_id, run.id, niche.id}
    assert Repo.get!(Niche, niche.id).status == :chosen
    assert Repo.get!(Run, run.id).status == :running
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "picking a niche tells the run's subscribers once, after the run is running with step 8 enqueued" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    run_id = run.id
    Research.subscribe(run)

    {:ok, _page} = Niches.choose(scope_for(run.account), niche.id)

    assert_receive {:run_updated, ^run_id}
    refute_receive {:run_updated, _run_id}
    assert Repo.get!(Run, run.id).status == :running
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "picking a niche again while its brief is being written enqueues no second step 8 job" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    scope = scope_for(run.account)

    {:ok, first_page} = Niches.choose(scope, niche.id)

    assert {:ok, %Page{id: page_id, status: :writing}} = Niches.choose(scope, niche.id)
    assert page_id == first_page.id
    assert [_one_job] = all_enqueued(worker: WriteBrief)

    assert Page
           |> from(as: :page)
           |> where([page: page], page.run_id == ^run.id)
           |> Repo.aggregate(:count) == 1
  end

  test "picking a niche whose page is written returns it without writing it again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :ready)

    assert {:ok, %Page{id: page_id, status: :ready}} = Niches.choose(scope_for(run.account), niche.id)
    assert page_id == page.id
    assert all_enqueued(worker: WriteBrief) == []
    assert Repo.get!(Run, run.id).status == :awaiting_choice
  end

  test "picking a niche whose page failed writes it again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :failed, error: "Model zwrócił niepoprawny brief", brief: nil)

    assert {:ok, %Page{id: page_id, status: :writing, error: nil}} = Niches.choose(scope_for(run.account), niche.id)
    assert page_id == page.id
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "picking a niche whose page is being published returns it and leaves the run alone" do
    run = insert(:run, status: :done, steps: build_run_steps(Map.new(1..9, &{&1, :done})))
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche, status: :publishing)

    assert {:ok, %Page{id: page_id, status: :publishing}} = Niches.choose(scope_for(run.account), niche.id)
    assert page_id == page.id
    assert Repo.get!(Page, page.id).status == :publishing
    assert Repo.get!(Run, run.id).status == :done
    assert all_enqueued(worker: WriteBrief) == []
  end

  test "another niche can't be picked while a page of the run is being published" do
    run =
      insert(:run, status: :running, steps: 1..8 |> Map.new(&{&1, :done}) |> Map.put(9, :running) |> build_run_steps())

    published_niche = insert(:niche, run: run, status: :chosen)
    insert(:page, run: run, niche: published_niche, status: :publishing)
    niche = insert(:niche, run: run)

    assert {:error, :run_busy} = Niches.choose(scope_for(run.account), niche.id)
    assert Repo.get!(Niche, niche.id).status == :proposed
    assert Pages.page_for_niche(niche) == nil
    assert all_enqueued() == []
  end

  test "a niche can't be picked while a step of a failed run is still queued" do
    run =
      insert(:run, status: :failed, steps: 1..8 |> Map.new(&{&1, :done}) |> Map.put(9, :queued) |> build_run_steps())

    insert(:page, run: run, status: :publishing)
    niche = insert(:niche, run: run)

    assert {:error, :run_busy} = Niches.choose(scope_for(run.account), niche.id)
    assert Repo.get!(Niche, niche.id).status == :proposed
    assert Pages.page_for_niche(niche) == nil
    assert all_enqueued() == []
  end

  test "a niche can't be picked on a stopped run" do
    run = insert(:run, status: :stopped, steps: build_run_steps(Map.new(1..9, &{&1, :done})))
    insert(:page, run: run, status: :ready)
    niche = insert(:niche, run: run)

    assert {:error, :run_not_ready} = Niches.choose(scope_for(run.account), niche.id)
    assert Pages.page_for_niche(niche) == nil
    assert all_enqueued() == []
  end

  test "another Account's niche can't be picked and nothing changes" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)

    assert {:error, :not_found} = Niches.choose(scope_for(insert(:account)), niche.id)

    assert Repo.get!(Niche, niche.id).status == :proposed
    assert Repo.all(Page) == []
    assert all_enqueued() == []
  end

  test "a niche can't be picked while the run is still running its first steps" do
    run = insert(:run, status: :running, steps: build_run_steps(%{1 => :done, 2 => :running}))
    niche = insert(:niche, run: run)

    assert {:error, :run_not_ready} = Niches.choose(scope_for(run.account), niche.id)
    assert Repo.get!(Niche, niche.id).status == :proposed
    assert all_enqueued() == []
  end

  test "a second niche can't be picked while another page of the run is being written" do
    run = run_awaiting_choice()
    [first, second] = insert_list(2, :niche, run: run)
    scope = scope_for(run.account)
    {:ok, _page} = Niches.choose(scope, first.id)

    Run
    |> from(as: :run)
    |> where([run: stored_run], stored_run.id == ^run.id)
    |> Repo.update_all(set: [status: :awaiting_choice])

    assert {:error, :brief_in_progress} = Niches.choose(scope, second.id)
    assert Repo.get!(Niche, second.id).status == :proposed
    assert [_one_job] = all_enqueued(worker: WriteBrief)
  end

  test "a rejected niche can't be picked" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, status: :rejected)

    assert {:error, :not_choosable} = Niches.choose(scope_for(run.account), niche.id)
    assert all_enqueued() == []
  end

  test "a proposed niche can be rejected" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)

    assert {:ok, %Niche{id: niche_id, status: :rejected}} = Niches.reject(scope_for(run.account), niche.id)
    assert niche_id == niche.id
    assert Repo.get!(Niche, niche.id).status == :rejected
  end

  test "a chosen niche can't be rejected" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, status: :chosen)

    assert {:error, :not_rejectable} = Niches.reject(scope_for(run.account), niche.id)
    assert Repo.get!(Niche, niche.id).status == :chosen
  end

  test "another Account's niche can't be rejected" do
    niche = insert(:niche, run: run_awaiting_choice())

    assert {:error, :not_found} = Niches.reject(scope_for(insert(:account)), niche.id)
    assert Repo.get!(Niche, niche.id).status == :proposed
  end

  test "a niche is found only through its run's Account" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)

    assert %Niche{id: niche_id} = Niches.get_niche(scope_for(run.account), niche.id)
    assert niche_id == niche.id
    assert Niches.get_niche(scope_for(insert(:account)), niche.id) == nil
    assert Niches.get_niche(scope_for(run.account), "nie-liczba") == nil
  end

  test "a niche's page goes with it when step 4 runs again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche)
    run_phrase = insert(:run_phrase, run: run, niche: niche)

    {:ok, _counts} =
      Niches.store_grouping(run, %{
        niches: [%{name: "Nowa nisza", intent: nil, reading: nil, phrase_ids: [run_phrase.id]}],
        rejected: []
      })

    assert Repo.get(Page, page.id) == nil
    assert Pages.get_page(scope_for(run.account), page.id) == nil
  end

  test "a run stopped after Step 7 refuses a choice until it is resumed" do
    run = insert(:run, status: :stopped, steps: 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :queued) |> build_run_steps())
    niche = insert(:niche, run: run)

    assert {:error, :run_not_ready} = Niches.choose(scope_for(run.account), niche.id)
  end

  test "a run that failed before Step 7 refuses a choice" do
    run = insert(:run, status: :failed, steps: build_run_steps(%{1 => :done, 2 => :done, 3 => :failed}))
    niche = insert(:niche, run: run)

    assert {:error, :run_not_ready} = Niches.choose(scope_for(run.account), niche.id)
  end

  test "a run whose Step 8 failed lets the User choose again" do
    run = insert(:run, status: :failed, steps: 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :failed) |> build_run_steps())
    niche = insert(:niche, run: run)

    assert {:ok, %Page{status: :writing}} = Niches.choose(scope_for(run.account), niche.id)
  end

  test "the results list of Niches has each one's monthly Volume, CPC and pooled competition" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run, score: Decimal.new("6.2"))
    first = phrase_in_niche(run, niche, %{volume: 130, cpc: "0.40"})
    second = phrase_in_niche(run, niche, %{volume: 70, cpc: nil})
    insert(:serp_assessment, run: run, phrase: first.phrase, labels: labels(%{"forum" => 2, "blog" => 1}))
    insert(:serp_assessment, run: run, phrase: second.phrase, labels: labels(%{"blog" => 2}))

    assert [%{niche: %Niche{id: niche_id}, volume: 200, cpc: cpc, competition: competition}] =
             Niches.list_summaries(run)

    assert niche_id == niche.id
    assert Decimal.equal?(cpc, Decimal.new("0.40"))
    assert competition == %{verdict: :weak, holders: "blogi, fora"}
  end

  test "the results list keeps rejected Niches and says when none of a Niche's Phrases was checked" do
    run = run_awaiting_choice()
    rejected = insert(:niche, run: run, status: :rejected, score: Decimal.new("7.1"))
    unchecked = insert(:niche, run: run, score: Decimal.new("3.3"))
    phrase_in_niche(run, unchecked, %{volume: 40, cpc: "0.20"})

    assert [first, second] = Niches.list_summaries(run)
    assert %{niche: %Niche{id: rejected_id}, volume: 0, cpc: nil} = first
    assert %{niche: %Niche{id: unchecked_id}, competition: nil} = second
    assert {rejected_id, unchecked_id} == {rejected.id, unchecked.id}
  end

  test "a Niche's detail lists its kept Phrases with Volumes, CPC and who holds their top 10" do
    run = insert(:run, status: :awaiting_choice, city: "Płock", city_location_code: 9_990_123, steps: scored_steps())
    niche = insert(:niche, run: run)
    checked = phrase_in_niche(run, niche, %{volume: 90, cpc: "0.30"})
    insert(:metrics, phrase: checked.phrase, location_code: 9_990_123, search_volume: 9)
    unchecked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    phrase_in_niche(run, niche, %{volume: 500, cpc: "1.00", status: :rejected})
    insert(:serp_assessment, run: run, phrase: checked.phrase, labels: labels(%{"portal" => 3, "blog" => 1}))

    detail = Niches.niche_detail(run, niche)

    assert [first, second] = detail.phrases
    assert %{id: first_id, volume: 90, city_volume: 9, holders: "portale, blogi", currency: "USD"} = first
    assert first_id == checked.id
    assert Decimal.equal?(first.cpc, Decimal.new("0.30"))
    assert %{volume: 30, city_volume: nil, holders: nil, cpc: nil} = second
    assert second.phrase == unchecked.phrase.phrase
    assert detail.page == nil
  end

  test "a Niche's detail marks its Quick Wins and counts them" do
    run = insert(:run, mode: :existing_site, domain: "strona-testowa.pl", status: :awaiting_choice, steps: scored_steps())
    niche = insert(:niche, run: run)
    quick_win = phrase_in_niche(run, niche, %{volume: 90, cpc: nil})
    top = phrase_in_niche(run, niche, %{volume: 60, cpc: nil})
    unranked = phrase_in_niche(run, niche, %{volume: 30, cpc: nil})
    quick_win |> Ecto.Changeset.change(current_position: Decimal.new("12.0")) |> Repo.update!()
    top |> Ecto.Changeset.change(current_position: Decimal.new("2.0")) |> Repo.update!()

    detail = Niches.niche_detail(run, niche)

    assert Enum.map(detail.phrases, &{&1.id, &1.quick_win?}) == [
             {quick_win.id, true},
             {top.id, false},
             {unranked.id, false}
           ]

    assert detail.quick_win_count == 1
  end

  test "a Niche's detail counts the most direct competitors in one checked top 10" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    first = phrase_in_niche(run, niche, %{volume: 50, cpc: nil})
    second = phrase_in_niche(run, niche, %{volume: 20, cpc: nil})
    insert(:serp_assessment, run: run, phrase: first.phrase, labels: labels(%{"direct_competitor" => 2, "blog" => 3}))
    insert(:serp_assessment, run: run, phrase: second.phrase, labels: labels(%{"direct_competitor" => 3, "forum" => 1}))

    assert %{direct_competitors: 3} = Niches.niche_detail(run, niche)
  end

  test "a Niche's detail has no competitor count when none of its Phrases was checked" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, %{volume: 50, cpc: nil})

    assert %{direct_competitors: nil, best_position: nil} = Niches.niche_detail(run, niche)
  end

  test "a Niche's detail has the best Current Position among its Phrases and its page" do
    run =
      insert(:run, mode: :existing_site, domain: "przyklad-testowy.pl", status: :awaiting_choice, steps: scored_steps())

    niche = insert(:niche, run: run, status: :chosen)
    page = insert(:page, run: run, niche: niche)

    for position <- ["14.2", "9.6", nil] do
      run_phrase = phrase_in_niche(run, niche, %{volume: 10, cpc: nil})
      run_phrase |> Ecto.Changeset.change(current_position: position && Decimal.new(position)) |> Repo.update!()
    end

    detail = Niches.niche_detail(run, niche)

    assert Decimal.equal?(detail.best_position, Decimal.new("9.6"))
    assert detail.page.id == page.id
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

  defp run_awaiting_choice do
    insert(:run, status: :awaiting_choice, steps: scored_steps())
  end

  defp scored_steps, do: build_run_steps(Map.new(1..7, &{&1, :done}))

  defp phrase_in_niche(run, niche, metrics) do
    phrase = insert(:phrase, phrase: unique_phrase_text("fraza niszy"))

    if metrics.volume || metrics.cpc do
      insert(:metrics,
        phrase: phrase,
        location_code: run.location_code,
        search_volume: metrics.volume,
        cpc: metrics.cpc && Decimal.new(metrics.cpc)
      )
    end

    insert(:run_phrase, run: run, phrase: phrase, niche: niche, status: Map.get(metrics, :status, :kept))
  end

  defp labels(counts_by_page_type) do
    counts_by_page_type
    |> Enum.flat_map(fn {page_type, count} -> List.duplicate(page_type, count) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {page_type, position} -> %{"position" => position, "page_type" => page_type} end)
  end
end
