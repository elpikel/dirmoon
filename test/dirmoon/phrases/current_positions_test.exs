defmodule Dirmoon.Phrases.CurrentPositionsTest do
  use Dirmoon.DataCase, async: true

  import Mox

  alias Dirmoon.Accounts
  alias Dirmoon.Phrases.CurrentPositions
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.SearchConsole

  @domain "kancelaria-testowa.pl"
  @refresh_token "1//refresh-token-plaintext"
  @access_token "ya29.access-token-plaintext"

  test "a connection that can read the domain gives the positions alone and nothing is bought" do
    run = existing_site_run()
    connect(run)
    quick_win = run_phrase(run, "adwokat rozwód")
    top = run_phrase(run, "adwokat gdańsk")
    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 0, fn _request -> flunk("nothing is bought") end)
    stub_query(fn _request -> sc_rows([sc_row(text(quick_win), 12.345), sc_row(text(top), 3.2)]) end)

    assert {:ok, %{result: result, output: output}} = CurrentPositions.fetch(run)

    assert result == "2 searches where your site shows up on Google, 1 at positions 8–20 (from Search Console)"
    assert %{"sources" => ["search_console"], "matched" => 2, "quick_wins" => 1, "rows" => [_, _]} = output
    assert %{"start_date" => start_date, "end_date" => end_date} = output
    assert start_date == Date.utc_today() |> Date.add(-90) |> Date.to_iso8601()
    assert end_date == Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
    assert %RunPhrase{current_position_url: nil} = stored(quick_win)
    assert Decimal.equal?(stored(quick_win).current_position, Decimal.new("12.3"))
    refute Repo.exists?(api_requests(run))
    verify!()
  end

  test "Search Console's positions win over a first page where the site shows up" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "adwokat spadki")
    first_page(run, phrase, [result(2, "www." <> @domain)])
    stub_query(fn _request -> sc_rows([sc_row(text(phrase), 14.0)]) end)

    assert {:ok, %{output: %{"sources" => ["search_console"]}}} = CurrentPositions.fetch(run)

    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("14.0"))
  end

  test "Search Console rows that match none of the run's searches still finish without buying anything" do
    run = existing_site_run()
    connect(run)
    run_phrase(run, "adwokat alimenty")
    stub_query(fn _request -> sc_rows([sc_row(unique_phrase_text("kancelaria nieznana"), 9.0)]) end)

    assert {:ok, %{result: "Your site doesn't show up yet for these searches", output: output}} =
             CurrentPositions.fetch(run)

    assert %{"sources" => ["search_console"], "matched" => 0, "quick_wins" => 0} = output
  end

  test "without a connection the positions come from the ranked phrases, through the ledger, with the address that ranks" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat rozwód")
    url = "https://www.#{@domain}/rozwody"

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn request ->
      assert request == %{domain: @domain, location_code: run.location_code, language_code: "pl", limit: 1000}
      ranked([ranked_row(String.upcase(text(phrase)), 11, url)], "0.0125")
    end)

    assert {:ok, %{result: result, output: output}} = CurrentPositions.fetch(run)

    assert result == "1 search where your site shows up on Google, 1 at positions 8–20 (from Google's results)"

    assert output == %{
             "sources" => ["ranked_phrases", "first_pages"],
             "search_console" => "Search Console is not connected",
             "matched" => 1,
             "quick_wins" => 1
           }

    assert %RunPhrase{current_position_url: ^url} = stored(phrase)
    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("11.0"))

    assert %ApiRequest{service: "dataforseo", cost: cost} =
             Repo.get_by!(ApiRequest, run_id: run.id, operation: "ranked_phrases")

    assert Decimal.equal?(cost, Decimal.new("0.0125"))
  end

  test "a city run asks for the ranked phrases in its country" do
    run = existing_site_run(%{city: "Gdańsk", city_location_code: 1_011_581})

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn %{location_code: location_code} ->
      assert location_code == run.location_code
      ranked([])
    end)

    assert {:ok, _outcome} = CurrentPositions.fetch(run)
  end

  test "running the step again replays the ranked phrases instead of paying twice" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat gdańsk")
    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn _request -> ranked([ranked_row(text(phrase), 4, url())]) end)

    assert {:ok, %{output: %{"matched" => 1}}} = CurrentPositions.fetch(run)
    assert {:ok, %{output: %{"matched" => 1}}} = CurrentPositions.fetch(run)

    assert Repo.aggregate(api_requests(run), :count) == 1
    verify!()
  end

  test "Search Console without access to the domain falls back to the ranked phrases" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "adwokat alimenty")
    stub_query(fn _request -> {:error, :forbidden} end)
    stub_ranked(fn _request -> ranked([ranked_row(text(phrase), 15, url())]) end)

    assert {:ok, %{output: %{"search_console" => "No access to kancelaria-testowa.pl in Search Console"}}} =
             CurrentPositions.fetch(run)

    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("15.0"))
  end

  test "a connection needing a reconnect falls back to the ranked phrases" do
    run = existing_site_run()
    connect(run)
    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn _request -> {:error, :invalid_grant} end)
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{output: %{"search_console" => "The Search Console connection expired, connect again"}}} =
             CurrentPositions.fetch(run)
  end

  test "Search Console answering no rows falls back to the ranked phrases" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "adwokat spadki")
    stub_query(fn _request -> sc_rows([]) end)
    stub_ranked(fn _request -> ranked([ranked_row(text(phrase), 9, url())]) end)

    assert {:ok, %{output: output}} = CurrentPositions.fetch(run)

    assert %{
             "sources" => ["ranked_phrases", "first_pages"],
             "search_console" => "Search Console has no data for this domain"
           } =
             output

    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("9.0"))
  end

  test "a first page where the site shows up gives its position and address to a search the ranked phrases miss" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat rozwód")
    snapshot_url = "https://www.#{@domain}/oferta"
    first_page(run, phrase, [result(3, "konkurent.example"), %{result(6, "www." <> @domain) | "url" => snapshot_url}])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{result: result}} = CurrentPositions.fetch(run)

    assert result == "1 search where your site shows up on Google, 0 at positions 8–20 (from Google's results)"
    assert %RunPhrase{current_position_url: ^snapshot_url} = stored(phrase)
    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("6.0"))
  end

  test "a first page giving an international site's domain in its Unicode form counts as the site" do
    run = existing_site_run(%{domain: "xn--w-uga1v8h.pl"})
    phrase = run_phrase(run, "adwokat rozwód")
    first_page(run, phrase, [result(4, "www.żółw.pl")])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{output: %{"matched" => 1}}} = CurrentPositions.fetch(run)
    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("4.0"))
  end

  test "Search Console without access to an international domain names it in its Unicode form" do
    run = existing_site_run(%{domain: "xn--w-uga1v8h.pl"})
    connect(run)
    stub_query(fn _request -> {:error, :forbidden} end)
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{output: %{"search_console" => "No access to żółw.pl in Search Console"}}} =
             CurrentPositions.fetch(run)
  end

  test "the site's best result on a first page counts" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat gdańsk")
    first_page(run, phrase, [result(9, @domain), result(4, @domain)])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, _outcome} = CurrentPositions.fetch(run)

    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("4.0"))
  end

  test "the ranked phrases win over a first page for the same search" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat alimenty")
    first_page(run, phrase, [result(2, @domain)])
    stub_ranked(fn _request -> ranked([ranked_row(text(phrase), 12, url())]) end)

    assert {:ok, _outcome} = CurrentPositions.fetch(run)

    assert Decimal.equal?(stored(phrase).current_position, Decimal.new("12.0"))
    assert stored(phrase).current_position_url == url()
  end

  test "ranked phrases DataForSEO can't give leave the first pages only, recorded with their cost so they are not asked for again" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat spadki")
    first_page(run, phrase, [result(9, @domain)])

    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 1, fn _request ->
      unavailable("DataForSEO: Invalid Field: 'location_code'.", "0.012")
    end)

    assert {:ok, %{result: result, output: output}} = CurrentPositions.fetch(run)

    assert result == "1 search where your site shows up on Google, 1 at positions 8–20 (from Google's first pages only)"

    assert output == %{
             "sources" => ["first_pages"],
             "ranked_phrases_unavailable" => "DataForSEO: Invalid Field: 'location_code'.",
             "search_console" => "Search Console is not connected",
             "matched" => 1,
             "quick_wins" => 1
           }

    assert %ApiRequest{cost: cost} = Repo.get_by!(ApiRequest, run_id: run.id, operation: "ranked_phrases")
    assert Decimal.equal?(cost, Decimal.new("0.012"))

    assert {:ok, %{output: %{"sources" => ["first_pages"], "matched" => 1}}} = CurrentPositions.fetch(run)
    assert Repo.aggregate(api_requests(run), :count) == 1
    verify!()
  end

  test "a site on no first page while the ranked phrases were unavailable is not said to show up nowhere" do
    run = existing_site_run()
    run_phrase(run, "adwokat rozwód")
    stub_ranked(fn _request -> unavailable("DataForSEO: status 40501", "0") end)

    assert {:ok, %{result: result}} = CurrentPositions.fetch(run)

    assert result ==
             "Your site isn't on Google's first page for these searches; where it ranks further down couldn't be checked"
  end

  test "Demo Data without ranked phrases leaves the first pages only and records nothing" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat alimenty")
    first_page(run, phrase, [result(4, @domain)])
    stub_ranked(fn _request -> {:error, :not_in_demo_data} end)

    assert {:ok, %{output: output}} = CurrentPositions.fetch(run)

    assert %{
             "sources" => ["first_pages"],
             "ranked_phrases_unavailable" => "Demo Data has no ranked phrases",
             "matched" => 1
           } = output

    refute Repo.exists?(api_requests(run))
  end

  test "an address that ranks but is not a web address is not stored, while its position is" do
    run = existing_site_run()
    ranked_phrase = run_phrase(run, "adwokat rozwód")
    first_page_phrase = run_phrase(run, "adwokat gdańsk")

    first_page(run, first_page_phrase, [
      %{result(3, @domain) | "url" => "https://#{@domain}/" <> String.duplicate("a", 2_048)}
    ])

    stub_ranked(fn _request -> ranked([ranked_row(text(ranked_phrase), 6, "javascript:alert(1)")]) end)

    assert {:ok, %{output: %{"matched" => 2}}} = CurrentPositions.fetch(run)

    assert %RunPhrase{current_position_url: nil} = stored(ranked_phrase)
    assert Decimal.equal?(stored(ranked_phrase).current_position, Decimal.new("6.0"))
    assert %RunPhrase{current_position_url: nil} = stored(first_page_phrase)
  end

  test "a site that shows up nowhere finishes the step saying so" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat rozwód", %{current_position: Decimal.new("10.0")})
    first_page(run, phrase, [result(1, "konkurent.example")])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{result: "Your site doesn't show up yet for these searches", output: %{"matched" => 0}}} =
             CurrentPositions.fetch(run)

    assert stored(phrase).current_position == nil
  end

  test "a subdomain or a result without a domain on a first page is not the site" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat gdańsk")
    first_page(run, phrase, [result(1, "blog." <> @domain), result(2, nil)])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{output: %{"matched" => 0}}} = CurrentPositions.fetch(run)
  end

  test "another run's first pages are never read" do
    run = existing_site_run()
    phrase = run_phrase(run, "adwokat alimenty")
    first_page(existing_site_run(), phrase, [result(5, @domain)])
    stub_ranked(fn _request -> ranked([]) end)

    assert {:ok, %{output: %{"matched" => 0}}} = CurrentPositions.fetch(run)
  end

  test "ranked phrases outside the run add nothing to the shared market tables" do
    run = existing_site_run()
    outside_text = unique_phrase_text("fraza spoza badania")
    phrase = run_phrase(run, "adwokat spadki")
    first_page(run, phrase, [result(3, @domain)])
    shared_counts = shared_table_counts()
    stub_ranked(fn _request -> ranked([ranked_row(outside_text, 5, url())]) end)

    assert {:ok, _outcome} = CurrentPositions.fetch(run)

    refute Repo.get_by(Phrase, phrase: outside_text)
    assert shared_table_counts() == shared_counts
  end

  test "a DataForSEO without credentials fails the step" do
    run = existing_site_run()
    stub_ranked(fn _request -> {:error, :data_for_seo_not_configured} end)

    assert CurrentPositions.fetch(run) == {:error, :data_for_seo_not_configured}
  end

  test "a failed ranked phrases request is an error to retry and records nothing" do
    run = existing_site_run()
    stub_ranked(fn _request -> {:error, "DataForSEO: HTTP 500"} end)

    assert CurrentPositions.fetch(run) == {:error, "DataForSEO: HTTP 500"}
    refute Repo.get_by(ApiRequest, run_id: run.id, operation: "ranked_phrases")
  end

  test "a Search Console error to retry buys nothing" do
    run = existing_site_run()
    connect(run)
    stub_query(fn _request -> {:error, "Google Search Console: HTTP 500"} end)
    expect(Dirmoon.DataForSEOMock, :ranked_phrases, 0, fn _request -> flunk("nothing is bought") end)

    assert CurrentPositions.fetch(run) == {:error, "Google Search Console: HTTP 500"}
  end

  test "a New Idea run is skipped" do
    run = insert(:run, mode: :new_idea)

    assert CurrentPositions.fetch(run) == {:skip, "New idea, no site yet"}
  end

  defp existing_site_run(attrs \\ %{}) do
    insert(:run, Map.merge(%{mode: :existing_site, domain: @domain}, attrs))
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

  defp first_page(run, run_phrase, results) do
    snapshot = insert(:serp_snapshot, phrase: run_phrase.phrase, results: results)
    insert(:serp_assessment, run: run, phrase: run_phrase.phrase, serp_snapshot: snapshot)
  end

  defp result(position, domain) do
    %{"position" => position, "url" => "https://#{domain}/strona-#{position}", "domain" => domain, "title" => "Wynik"}
  end

  defp text(run_phrase), do: run_phrase.phrase.phrase

  defp url, do: "https://#{@domain}/kontakt"

  defp stub_query(fun), do: stub(Dirmoon.SearchConsoleMock, :query, fun)

  defp stub_ranked(fun), do: stub(Dirmoon.DataForSEOMock, :ranked_phrases, fun)

  defp sc_row(query, position), do: %{query: query, clicks: 3, impressions: 120, ctr: 0.025, position: position}

  defp sc_rows(rows), do: {:ok, %{rows: rows, raw: %{"rows" => []}}}

  defp ranked_row(phrase, position, url), do: %{phrase: phrase, position: position, url: url, search_volume: 40}

  defp ranked(rows, cost \\ "0.01"), do: {:ok, %{rows: rows, raw: %{"tasks" => []}, cost: Decimal.new(cost)}}

  defp unavailable(message, cost),
    do: {:error, {:ranked_phrases_unavailable, %{message: message, raw: %{"tasks" => []}, cost: Decimal.new(cost)}}}

  defp stored(run_phrase), do: Repo.get!(RunPhrase, run_phrase.id)

  defp api_requests(run) do
    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^run.id)
  end

  defp shared_table_counts do
    Map.new(["keywords", "keyword_metrics", "serp_snapshots"], fn table ->
      {table, Repo.query!("SELECT count(*) FROM #{table}").rows}
    end)
  end
end
