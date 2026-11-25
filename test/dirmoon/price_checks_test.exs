defmodule Dirmoon.PriceChecksTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.PriceChecks
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Workers.CheckCompetitorPrices

  test "the pages to read are direct competitors with a web address, one per domain at its best position" do
    first_pages = [
      %{
        id: 1,
        phrase: "wypożyczalnia łyżew",
        results: [
          result(%{position: 1, url: "https://portal-testowy.example/lodowiska", page_type: :portal}),
          result(%{position: 2, url: "https://www.lodowisko-a.example/cennik", page_type: :direct_competitor}),
          result(%{position: 3, url: "ftp://lodowisko-b.example/cennik", page_type: :direct_competitor}),
          result(%{position: 4, url: nil, page_type: :direct_competitor}),
          result(%{position: 6, url: "https://lodowisko-c.example/", page_type: :direct_competitor})
        ]
      },
      %{
        id: 2,
        phrase: "łyżwy gdańsk",
        results: [
          result(%{position: 1, url: "https://lodowisko-a.example/", page_type: :direct_competitor}),
          result(%{position: 5, url: "https://lodowisko-c.example/oferta", page_type: :direct_competitor}),
          result(%{position: 7, url: "https://", page_type: :direct_competitor})
        ]
      }
    ]

    assert PriceChecks.competitor_pages(first_pages) == [
             %{domain: "lodowisko-a.example", url: "https://lodowisko-a.example/", google_position: 1},
             %{domain: "lodowisko-c.example", url: "https://lodowisko-c.example/oferta", google_position: 5}
           ]
  end

  test "at most five competitor pages are read" do
    results =
      Enum.map(1..7, &result(%{position: &1, url: "https://konkurent-#{&1}.example/", page_type: :direct_competitor}))

    pages = PriceChecks.competitor_pages([%{id: 1, phrase: "fraza", results: results}])

    assert PriceChecks.page_limit() == 5
    assert Enum.map(pages, & &1.google_position) == [1, 2, 3, 4, 5]
  end

  test "starting a check stores its competitor pages, enqueues the work and tells subscribers" do
    run = scored_run()
    niche = insert(:niche, run: run)
    niche_with_competitors(run, niche, ["direct_competitor", "blog", "direct_competitor"])
    PriceChecks.subscribe(run)

    assert {:ok, %PriceCheck{status: :checking, competitor_pages: pages} = price_check} =
             PriceChecks.start(scope_for(run.account), niche.id)

    assert [
             %CompetitorPage{domain: "wynik-1.example", url: "https://wynik-1.example/strona", outcome: :waiting},
             %CompetitorPage{domain: "wynik-3.example", google_position: 3}
           ] = pages

    assert_enqueued(worker: CheckCompetitorPrices, args: %{price_check_id: price_check.id})
    niche_id = niche.id
    assert_received {:price_check_updated, ^niche_id}
    assert PriceChecks.get_for_niche(niche).id == price_check.id
  end

  test "asking again while a check runs or after it finished starts nothing new" do
    run = scored_run()
    niche = insert(:niche, run: run)
    niche_with_competitors(run, niche, ["direct_competitor"])
    scope = scope_for(run.account)
    {:ok, first} = PriceChecks.start(scope, niche.id)

    assert {:ok, %PriceCheck{id: same_id}} = PriceChecks.start(scope, niche.id)
    assert same_id == first.id

    first |> Ecto.Changeset.change(status: :done) |> Repo.update!()

    assert {:ok, %PriceCheck{id: ^same_id, status: :done}} = PriceChecks.start(scope, niche.id)
    assert [_one_job] = all_enqueued(worker: CheckCompetitorPrices)
    assert Repo.aggregate(PriceCheck, :count) == 1
  end

  test "a failed check runs again for the pages not read yet" do
    run = scored_run()
    niche = insert(:niche, run: run)
    failed = insert(:price_check, run: run, niche: niche, status: :failed, error: "No OpenAI API key")
    read = insert(:competitor_page, price_check: failed, outcome: :unreadable)
    PriceChecks.subscribe(run)

    assert {:ok, %PriceCheck{status: :checking, error: nil, competitor_pages: [page]}} =
             PriceChecks.start(scope_for(run.account), niche.id)

    assert page.id == read.id
    assert page.outcome == :unreadable
    assert_enqueued(worker: CheckCompetitorPrices, args: %{price_check_id: failed.id})
    assert_received {:price_check_updated, _niche_id}
  end

  test "a Niche of another Account or a malformed id is not found" do
    run = scored_run()
    niche = insert(:niche, run: run)
    niche_with_competitors(run, niche, ["direct_competitor"])
    stranger = scope_for(insert(:account))

    assert {:error, :not_found} = PriceChecks.start(stranger, niche.id)
    assert {:error, :not_found} = PriceChecks.start(stranger, "nie-liczba")
    assert PriceChecks.get_for_niche(niche) == nil
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  test "a run whose results are not ready yet is not checked" do
    run = insert(:run, steps: build_run_steps(Map.new(1..5, &{&1, :done})))
    niche = insert(:niche, run: run)
    niche_with_competitors(run, niche, ["direct_competitor"])

    assert {:error, :run_not_ready} = PriceChecks.start(scope_for(run.account), niche.id)
    assert PriceChecks.get_for_niche(niche) == nil
  end

  test "a Niche without direct competitors on Google's first page has nothing to check" do
    run = scored_run()
    niche = insert(:niche, run: run)
    niche_with_competitors(run, niche, ["blog", "forum"])

    assert {:error, :no_competitors} = PriceChecks.start(scope_for(run.account), niche.id)
    assert PriceChecks.get_for_niche(niche) == nil
    refute_enqueued(worker: CheckCompetitorPrices)
  end

  defp result(%{position: position, url: url, page_type: page_type}) do
    %{position: position, url: url, domain: "nieużywana.example", title: nil, page_type: page_type, page_type_name: nil}
  end

  defp scored_run do
    insert(:run, status: :awaiting_choice, steps: build_run_steps(Map.new(1..7, &{&1, :done})))
  end

  defp niche_with_competitors(run, niche, page_types) do
    phrase = insert(:phrase)
    insert(:run_phrase, run: run, phrase: phrase, niche: niche)

    labels =
      page_types
      |> Enum.with_index(1)
      |> Enum.map(fn {type, position} -> %{"position" => position, "page_type" => type} end)

    insert(:serp_assessment, run: run, phrase: phrase, labels: labels)
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)
end
