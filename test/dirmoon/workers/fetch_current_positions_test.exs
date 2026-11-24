defmodule Dirmoon.Workers.FetchCurrentPositionsTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Accounts
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.RunStep
  alias Dirmoon.SearchConsole
  alias Dirmoon.Workers.FetchCurrentPositions
  alias Dirmoon.Workers.ScoreNiches

  @domain "kancelaria-testowa.pl"
  @refresh_token "1//refresh-token-plaintext"
  @access_token "ya29.access-token-plaintext"

  test "an existing site's queries from the last 90 days are stored for the run and phrases ranking 8–20 are marked" do
    run = existing_site_run()
    connect(run)
    quick_win = run_phrase(run, "adwokat rozwód")
    top_phrase = run_phrase(run, "adwokat gdańsk")
    unmatched_query = unique_phrase_text("kancelaria nieznana")
    today = Date.utc_today()
    expected_start = Date.add(today, -90)
    expected_end = Date.add(today, -1)

    expect(Dirmoon.SearchConsoleMock, :query, 1, fn request ->
      assert %{site_url: "sc-domain:" <> @domain, start_date: ^expected_start, end_date: ^expected_end} = request
      assert request.access_token == @access_token
      assert request.row_limit == 5000

      rows([
        row(quick_win.phrase.phrase, 12.345),
        row(top_phrase.phrase.phrase, 3.2),
        row(unmatched_query, 9.0)
      ])
    end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, result: "1 fraza na pozycjach 8–20", output: output} = step(run, 6)

    assert %{"matched" => 2, "quick_wins" => 1, "start_date" => start_date, "end_date" => end_date} = output
    assert start_date == Date.to_iso8601(expected_start)
    assert end_date == Date.to_iso8601(expected_end)

    assert output["rows"] |> Enum.map(& &1["query"]) |> Enum.sort() ==
             Enum.sort([quick_win.phrase.phrase, top_phrase.phrase.phrase, unmatched_query])

    assert Enum.all?(output["rows"], &(Map.keys(&1) == ["clicks", "ctr", "impressions", "position", "query"]))
    assert Decimal.equal?(current_position(quick_win), Decimal.new("12.3"))
    assert Decimal.equal?(current_position(top_phrase), Decimal.new("3.2"))
  end

  test "the result counts phrases in positions 8–20 in Polish" do
    run = existing_site_run()
    connect(run)
    phrases = Enum.map(1..5, fn _index -> run_phrase(run, "porada prawna") end)

    stub_query(fn _request -> phrases |> Enum.map(&row(&1.phrase.phrase, 15.0)) |> rows() end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :done, result: "5 fraz na pozycjach 8–20", output: %{"quick_wins" => 5}} = step(run, 6)
  end

  test "positions are matched to phrases regardless of case and extra whitespace" do
    run = existing_site_run()
    connect(run)
    phrase = run_phrase(run, "rozwód bez orzekania")
    shouted_query = "  " <> (phrase.phrase.phrase |> String.upcase() |> String.replace(" ", "   ")) <> " "

    stub_query(fn _request -> rows([row(shouted_query, 9.0)]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert Decimal.equal?(current_position(phrase), Decimal.new("9.0"))
    assert %RunStep{result: "1 fraza na pozycjach 8–20"} = step(run, 6)
  end

  test "rejected phrases of the run get their current position too" do
    run = existing_site_run()
    connect(run)
    rejected = run_phrase(run, "adwokat za darmo", %{status: :rejected, rejection_reason: "Darmowe"})

    stub_query(fn _request -> rows([row(rejected.phrase.phrase, 11.0)]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert Decimal.equal?(current_position(rejected), Decimal.new("11.0"))
  end

  test "running the step again clears positions the site no longer has" do
    run = existing_site_run()
    connect(run)
    stale = run_phrase(run, "adwokat spadki", %{current_position: Decimal.new("10.0")})

    stub_query(fn _request -> rows([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert current_position(stale) == nil
  end

  test "a site without Search Console data finishes the step with a no-data result" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> rows([]) end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{
             status: :done,
             result: "Brak danych w Search Console dla tej domeny",
             output: %{"rows" => [], "matched" => 0, "quick_wins" => 0}
           } = step(run, 6)

    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "an account without a connection skips the step and the pipeline continues to Step 7" do
    run = existing_site_run()

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak połączenia z Search Console"} = step(run, 6)
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "another account's connection is never used for the run" do
    run = existing_site_run()
    other_run = existing_site_run()
    connect(other_run)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak połączenia z Search Console"} = step(run, 6)
  end

  test "a property the Google user can't access skips the step naming the domain and the pipeline continues" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :forbidden} end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak dostępu do kancelaria-testowa.pl w Search Console"} =
             step(run, 6)

    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a revoked or expired connection skips the step asking to reconnect" do
    run = existing_site_run()
    connect(run)

    expect(Dirmoon.SearchConsoleMock, :refresh_access_token, 1, fn _request -> {:error, :invalid_grant} end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Połączenie z Search Console wygasło, połącz ponownie"} = step(run, 6)
  end

  test "a connection whose refresh token no longer decrypts skips the step asking to reconnect" do
    run = existing_site_run()
    insert(:search_console_connection, account: run.account)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Połączenie z Search Console wygasło, połącz ponownie"} = step(run, 6)
  end

  test "a rejected access token fails the attempt so the job retries with a fresh token" do
    run = existing_site_run()
    connect(run)

    stub_query(fn _request -> {:error, :unauthorized} end)

    assert {:error, _reason} = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :running} = step(run, 6)
    refute_enqueued(worker: ScoreNiches)
  end

  test "Search Console without credentials skips the step" do
    run = existing_site_run()
    connect(run)

    stub(Dirmoon.SearchConsoleMock, :refresh_access_token, fn _request -> {:error, :search_console_not_configured} end)

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Search Console nie jest skonfigurowane"} = step(run, 6)
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

    assert %RunStep{status: :skipped, result: "Nowy pomysł, nie ma jeszcze strony"} = step(run, 6)
    refute_enqueued(worker: FetchCurrentPositions)
    assert_enqueued(worker: ScoreNiches, args: %{run_id: run.id})
  end

  test "a New Idea run that reaches this worker skips the step without calling Search Console" do
    run = insert(:run, mode: :new_idea, steps: build_run_steps(Map.new(1..5, &{&1, :done})))

    assert :ok = perform_job(FetchCurrentPositions, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Nowy pomysł, nie ma jeszcze strony"} = step(run, 6)
  end

  defp existing_site_run do
    insert(:run, mode: :existing_site, domain: @domain, steps: build_run_steps(Map.new(1..5, &{&1, :done})))
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

  defp row(query, position), do: %{query: query, clicks: 3, impressions: 120, ctr: 0.025, position: position}

  defp rows(rows), do: {:ok, %{rows: rows, raw: %{"rows" => []}}}

  defp current_position(run_phrase), do: Repo.get!(RunPhrase, run_phrase.id).current_position

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
