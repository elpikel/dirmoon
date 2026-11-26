defmodule Dirmoon.Workers.FetchCurrentPositionsTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Accounts
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.RunStep
  alias Dirmoon.SearchConsole
  alias Dirmoon.Workers.FetchCurrentPositions
  alias Dirmoon.Workers.MatchSitePages
  alias Dirmoon.Workers.ScoreNiches

  @domain "kancelaria-testowa.pl"
  @refresh_token "1//refresh-token-plaintext"
  @access_token "ya29.access-token-plaintext"

  test "an existing site's Search Console queries from the last 90 days set the run's positions" do
    run = existing_site_run()
    connect(run)
    quick_win = run_phrase(run, "adwokat rozwód")
    top_phrase = run_phrase(run, "adwokat gdańsk")
    unmatched_query = unique_phrase_text("kancelaria nieznana")
    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 0, fn _request -> flunk("nothing is bought") end)

    stub_query(fn _request ->
      rows([row(quick_win.phrase.phrase, 12.345), row(top_phrase.phrase.phrase, 3.2), row(unmatched_query, 9.0)])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "2 searches where your site shows up on Google, 1 at positions 8–20 (from Search Console)",
             output: output
           } = step(run, 6)

    assert %{"sources" => ["search_console"], "matched" => 2, "quick_wins" => 1} = output

    assert output["rows"] |> Enum.map(& &1["query"]) |> Enum.sort() ==
             Enum.sort([quick_win.phrase.phrase, top_phrase.phrase.phrase, unmatched_query])

    assert Enum.all?(output["rows"], &(Map.keys(&1) == ["clicks", "ctr", "impressions", "position", "query"]))
    assert Decimal.equal?(current_position(quick_win), Decimal.new("12.3"))
    assert Decimal.equal?(current_position(top_phrase), Decimal.new("3.2"))
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
    verify!()
  end

  test "when the step is done the matching of the site's pages to the Niches is enqueued, and the step goes on as before" do
    run = existing_site_run()
    stub_ranked(fn _request -> ranked([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done} = step(run, 6)
    assert_enqueued(worker: MatchSitePages, args: %{run_id: run.id})
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a step that fails its attempt enqueues no matching" do
    run = existing_site_run()
    stub_ranked(fn _request -> {:error, "DataForSEO: HTTP 500"} end)

    assert {:error, "DataForSEO: HTTP 500"} = perform_job(FetchCurrentPositions, %{run_id: run.id}, attempt: 1)

    refute_enqueued(worker: MatchSitePages)
  end

  test "a decimal click-through rate and the date window are stored as strings in the step output" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "adwokat rozwód")

    stub_query(fn _request -> rows([%{row(phrase.phrase.phrase, 12.0) | ctr: Decimal.new("0.025")}]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert [%{"rows" => [%{"ctr" => "0.025", "position" => 12.0}], "start_date" => start_date}] =
             stored_json(%{table: "run_steps", column: "output", where: "run_id = $1 AND number = 6", value: run.id})

    assert start_date == today_minus(90)
  end

  test "positions are matched to phrases regardless of case and extra whitespace" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "rozwód bez orzekania")
    shouted_query = "  " <> (phrase.phrase.phrase |> String.upcase() |> String.replace(" ", "   ")) <> " "

    stub_query(fn _request -> rows([row(shouted_query, 9.0)]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert Decimal.equal?(current_position(phrase), Decimal.new("9.0"))
  end

  test "rejected phrases of the run get their current position too" do
    run = existing_site_run()
    connect(run)
    rejected = run_phrase(run, "adwokat za darmo", %{status: :rejected, rejection_reason: "Darmowe"})

    stub_query(fn _request -> rows([row(rejected.phrase.phrase, 11.0)]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert Decimal.equal?(current_position(rejected), Decimal.new("11.0"))
  end

  test "an account without a connection gets its positions from the ranked phrases and the step is done" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat spadki")
    url = "https://#{@domain}/spadki"

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn %{domain: @domain} ->
      ranked([%{phrase: phrase.phrase.phrase, position: 16, url: url, search_volume: 30}])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "1 search where your site shows up on Google, 1 at positions 8–20 (from Google's results)",
             output: %{
               "sources" => ["ranked_phrases", "first_pages"],
               "search_console" => "Search Console is not connected"
             }
           } = step(run, 6)

    assert %RunPhrase{current_position_url: ^url} = Repo.get!(RunPhrase, phrase.id)
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a first page of the run with the site on it gives that search its position and address" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat rozwód")
    url = "https://www.#{@domain}/rozwody"
    first_page(run, phrase, [%{"position" => 7, "url" => url, "domain" => "www." <> @domain, "title" => "Rozwody"}])
    stub_ranked(fn _request -> ranked([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "1 search where your site shows up on Google, 0 at positions 8–20 (from Google's results)"
           } =
             step(run, 6)

    assert %RunPhrase{current_position_url: ^url} = Repo.get!(RunPhrase, phrase.id)
    assert Decimal.equal?(current_position(phrase), Decimal.new("7.0"))
  end

  test "a run whose domain was stored in its Unicode form asks for and finds the site in its ASCII form" do
    run = existing_site_run("żółw.pl")
    ranked_phrase = run_phrase(run, "hotel dla psów")
    first_page_phrase = run_phrase(run, "hotel dla kotów")
    ranked_url = "https://xn--w-uga1v8h.pl/psy"
    first_page_url = "https://www.xn--w-uga1v8h.pl/koty"

    first_page(run, first_page_phrase, [
      %{"position" => 5, "url" => first_page_url, "domain" => "www.xn--w-uga1v8h.pl", "title" => "Koty"}
    ])

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn %{domain: "xn--w-uga1v8h.pl"} ->
      ranked([%{phrase: ranked_phrase.phrase.phrase, position: 11, url: ranked_url, search_volume: 30}])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"matched" => 2}} = step(run, 6)
    assert %RunPhrase{current_position_url: ^ranked_url} = Repo.get!(RunPhrase, ranked_phrase.id)
    assert %RunPhrase{current_position_url: ^first_page_url} = Repo.get!(RunPhrase, first_page_phrase.id)
  end

  test "a run whose domain was stored in its Unicode form asks Search Console for its ASCII domain property" do
    run = existing_site_run("żółw.pl")
    connect(run)
    phrase = run_phrase(run, "hotel dla psów")

    expect(Dirmoon.SearchConsoleMock, :query, 1, fn %{site_url: "sc-domain:xn--w-uga1v8h.pl"} ->
      rows([row(phrase.phrase.phrase, 4.0)])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"sources" => ["search_console"]}} = step(run, 6)
    assert Decimal.equal?(current_position(phrase), Decimal.new("4.0"))
  end

  test "the ranked phrases are paid once and count in the run's API Cost, even when the step runs again" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat spadki")

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn _request ->
      ranked([%{phrase: phrase.phrase.phrase, position: 12, url: "https://#{@domain}/spadki", search_volume: 30}])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})
    wait_again(run, 6)
    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"matched" => 1}} = step(run, 6)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.01"))
    verify!()
  end

  test "finding the site's positions leaves the shared market tables unchanged" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat alimenty")
    first_page(run, phrase, [%{"position" => 3, "url" => "https://#{@domain}/", "domain" => @domain, "title" => "Start"}])
    outside_text = unique_phrase_text("fraza spoza badania")
    shared = shared_market_rows()

    stub_ranked(fn _request ->
      ranked([%{phrase: outside_text, position: 5, url: "https://#{@domain}/inne", search_volume: 20}])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert shared_market_rows() == shared
  end

  test "ranked phrases DataForSEO fails to give leave the first pages only, the step done and the request not sent again" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat rozwód")
    first_page(run, phrase, [%{"position" => 9, "url" => "https://#{@domain}/", "domain" => @domain, "title" => "Start"}])

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn _request ->
      {:error,
       {:ranked_phrases_unavailable,
        %{message: "DataForSEO: Something never documented.", raw: %{"tasks" => []}, cost: Decimal.new("0.012")}}}
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "1 search where your site shows up on Google, 1 at positions 8–20 (from Google's first pages only)",
             output: %{
               "sources" => ["first_pages"],
               "ranked_phrases_unavailable" => "DataForSEO: Something never documented."
             }
           } = step(run, 6)

    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})

    wait_again(run, 6)
    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, output: %{"sources" => ["first_pages"]}} = step(run, 6)
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.012"))
    verify!()
  end

  test "Demo Data without ranked phrases leaves the first pages only and never says the site shows up nowhere" do
    run = existing_site_run()
    run_phrase(run, "adwokat spadki")
    stub_ranked(fn _request -> {:error, :not_in_demo_data} end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result:
               "Your site isn't on Google's first page for these searches; where it ranks further down couldn't be checked",
             output: %{"sources" => ["first_pages"], "ranked_phrases_unavailable" => "Demo Data has no ranked phrases"}
           } = step(run, 6)

    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a property the Google user can't access falls back and the step is done, not skipped" do
    run = existing_site_run()
    connect(run)
    stub_query(fn _request -> {:error, :forbidden} end)
    stub_ranked(fn _request -> ranked([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, result: "Your site doesn't show up yet for these searches"} = step(run, 6)
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "running the step again clears positions the site no longer has" do
    run = existing_site_run()
    stale = run_phrase(run, "adwokat spadki", %{current_position: Decimal.new("10.0")})
    stub_ranked(fn _request -> ranked([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert current_position(stale) == nil
  end

  test "a rejected access token fails the attempt so the job retries with a fresh token" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :unauthorized} end)

    assert {:error, _reason} = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :running} = step(run, 6)
    refute_enqueued(worker: ScoreNiches)
  end

  test "a failed ranked phrases request fails the attempt so the job retries" do
    run = existing_site_run()
    stub_ranked(fn _request -> {:error, "DataForSEO: HTTP 500"} end)

    assert {:error, "DataForSEO: HTTP 500"} = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :running} = step(run, 6)
    refute_enqueued(worker: ScoreNiches)
  end

  test "a DataForSEO without credentials fails the step and the run at once" do
    run = existing_site_run()
    stub_ranked(fn _request -> {:error, :data_for_seo_not_configured} end)

    assert {:cancel, :data_for_seo_not_configured} = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "No DataForSEO credentials"} = step(run, 6)
  end

  test "the access token and refresh token are stored nowhere in the step" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "adwokat alimenty")

    stub_query(fn _request -> rows([row(phrase.phrase.phrase, 14.0)]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    stored_step = inspect(step(run, 6), limit: :infinity, printable_limit: :infinity)
    refute stored_step =~ @access_token
    refute stored_step =~ @refresh_token
  end

  test "a New Idea run skips Step 6 without this worker and goes on to Step 7" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(Map.new(1..5, &{&1, :done})))

    :ok = Pipeline.advance(run)

    assert %RunStep{status: :skipped, result: "New idea, no site yet"} = step(run, 6)
    refute_enqueued(worker: FetchCurrentPositions)
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a New Idea run that reaches this worker skips the step without looking anything up" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(Map.new(1..5, &{&1, :done})))

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "New idea, no site yet"} = step(run, 6)
    refute_enqueued(worker: MatchSitePages)
  end

  defp existing_site_run(domain \\ @domain) do
    insert(:run, mode: :existing_site, domain: domain, steps: build_run_steps(Map.new(1..5, &{&1, :done})))
  end

  defp connect(run) do
    scope =
      :membership
      |> insert(account: run.account)
      |> Map.fetch!(:user)
      |> Accounts.scope_for_user()

    stub(Dirmoon.SearchConsoleMock, :exchange_code, fn _request ->
      {:ok, %{refresh_token: @refresh_token, access_token: @access_token, email: unique_user_email()}}
    end)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn %{refresh_token: @refresh_token} ->
      {:ok, %{access_token: @access_token, expires_in: 3599}}
    end)

    {:ok, _connection} = SearchConsole.connect(scope, %{code: "kod", redirect_uri: "http://localhost/callback"})
  end

  defp run_phrase(run, text, attrs \\ %{}) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text), language_code: run.language_code)
    :run_phrase |> insert(Map.merge(%{run: run, phrase: phrase}, attrs)) |> Repo.preload(:phrase)
  end

  defp stub_query(fun), do: stub(Dirmoon.SearchConsoleMock, :query, fun)

  defp stub_ranked(fun), do: stub(Dirmoon.DataForSEOMock, :ranked_phrases, fun)

  defp ranked(rows), do: {:ok, %{rows: rows, raw: %{"tasks" => []}, cost: Decimal.new("0.01")}}

  defp row(query, position), do: %{query: query, clicks: 3, impressions: 120, ctr: 0.025, position: position}

  defp rows(rows), do: {:ok, %{rows: rows, raw: %{"rows" => []}}}

  defp today_minus(days), do: Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()

  defp current_position(run_phrase), do: Repo.get!(RunPhrase, run_phrase.id).current_position

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)

  defp wait_again(run, number) do
    run |> step(number) |> Ecto.Changeset.change(status: :waiting, result: nil, output: nil) |> Repo.update!()
  end

  defp first_page(run, run_phrase, results) do
    snapshot = insert(:serp_snapshot, phrase: run_phrase.phrase, results: results)
    insert(:serp_assessment, run: run, phrase: run_phrase.phrase, serp_snapshot: snapshot)
  end

  defp shared_market_rows do
    Map.new(["keywords", "keyword_metrics", "serp_snapshots"], fn table ->
      {table, Repo.query!("SELECT * FROM #{table} ORDER BY id").rows}
    end)
  end
end
