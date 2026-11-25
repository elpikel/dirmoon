defmodule DirmoonWeb.Controllers.RunExport.ShowTest do
  use DirmoonWeb.ConnCase, async: true

  @header "phrase,niche,country_volume,city_volume,cpc,currency,top10,verdict,position,quick_win,rejected,reason"

  test "the run's Phrases download as a UTF-8 CSV named after the run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)

    conn = get(conn, ~p"/app/runs/#{run}/export.csv")

    assert response(conn, 200)
    assert response_content_type(conn, :csv) =~ "charset=utf-8"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename="research-#{run.id}.csv")
  end

  test "the CSV starts with a byte order mark and the column header", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)

    body = conn |> get(~p"/app/runs/#{run}/export.csv") |> response(200)

    assert body == <<0xEF, 0xBB, 0xBF>> <> @header <> "\r\n"
  end

  test "a kept Phrase has its Niche, Volumes, CPC, top 10, verdict, position and whether it is a Quick Win", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, city: "Płock", city_location_code: 9_990_456)
    niche = insert(:niche, run: run, name: "Nisza testowa eksportu")
    phrase = insert(:phrase, phrase: unique_phrase_text("łódź na godziny"))
    insert(:metrics, phrase: phrase, search_volume: 1_234, cpc: Decimal.new("0.73"))
    insert(:metrics, phrase: phrase, location_code: 9_990_456, search_volume: 17)
    insert(:run_phrase, run: run, phrase: phrase, niche: niche, current_position: Decimal.new("12.5"))
    insert(:serp_assessment, run: run, phrase: phrase, verdict: :weak)

    lines = export_lines(conn, run)

    assert Enum.at(lines, 1) ==
             "#{phrase.phrase},Nisza testowa eksportu,1234,17,0.73,USD,guides and blogs,Weak,12.5,yes,no,"
  end

  test "Rejected Phrases come with their reason", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)
    phrase = insert(:phrase, phrase: unique_phrase_text("kurs żeglarski"))
    insert(:run_phrase, run: run, phrase: phrase, status: :rejected, rejection_reason: "poza ofertą testową")

    assert export_lines(conn, run) == [@header, "#{phrase.phrase},,,,,,,,,no,yes,poza ofertą testową"]
  end

  test "a Phrase ranked outside positions 8 to 20 is not a Quick Win in the CSV", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, mode: :existing_site, domain: "strona-testowa.pl")
    phrase = insert(:phrase, phrase: unique_phrase_text("czarter jachtu"))
    insert(:run_phrase, run: run, phrase: phrase, current_position: Decimal.new("3.0"))

    assert export_lines(conn, run) == [@header, "#{phrase.phrase},,,,,,,,3.0,no,no,"]
  end

  test "a cell with a comma, a quote or a line break is quoted", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)
    niche = insert(:niche, run: run, name: ~s(Rejsy, "czartery"\ni kursy))
    insert(:run_phrase, run: run, niche: niche)

    body = conn |> get(~p"/app/runs/#{run}/export.csv") |> response(200)

    assert body =~ ~s(,"Rejsy, ""czartery""\ni kursy",)
  end

  test "a cell a spreadsheet would run as a formula starts with an apostrophe", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account)
    phrase = insert(:phrase, phrase: unique_phrase_text("=HYPERLINK(\"http://zly.example\")"))
    insert(:run_phrase, run: run, phrase: phrase, status: :rejected, rejection_reason: "@SUM(A1:A2)")
    insert(:run_phrase, run: run, status: :rejected, rejection_reason: "+48 test")

    body = conn |> get(~p"/app/runs/#{run}/export.csv") |> response(200)

    assert body =~ ~s|"'=HYPERLINK(""http://zly.example"")|
    assert body =~ ",yes,'@SUM(A1:A2)\r\n"
    assert body =~ ",yes,'+48 test\r\n"
  end

  test "another Account's run is not found", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    run = insert(:run)
    insert(:run_phrase, run: run)

    conn = get(conn, ~p"/app/runs/#{run}/export.csv")

    assert response(conn, 404) == "Not Found"
  end

  test "a malformed run id is not found", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    assert conn |> get(~p"/app/runs/nie-liczba/export.csv") |> response(404) == "Not Found"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    run = insert(:run)

    conn = get(conn, ~p"/app/runs/#{run}/export.csv")

    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp export_lines(conn, run) do
    <<0xEF, 0xBB, 0xBF>> <> body = conn |> get(~p"/app/runs/#{run}/export.csv") |> response(200)
    String.split(body, "\r\n", trim: true)
  end
end
