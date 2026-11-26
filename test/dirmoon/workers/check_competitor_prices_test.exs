defmodule Dirmoon.Workers.CheckCompetitorPricesTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.PriceChecks
  alias Dirmoon.PriceChecks.CompetitorOffer
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.CheckCompetitorPrices

  @page_text "Cennik Wypożyczenie łyżew: 15 zł za godzinę. Ostrzenie łyżew 20 zł."

  test "each page's verified prices are stored, an unreadable page is noted and the check is done" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example", "lodowisko-b.example"]})
    PriceChecks.subscribe(run)

    expect(Dirmoon.WebPageMock, :fetch, 2, fn
      "https://lodowisko-a.example/cennik" -> {:ok, html_page("https://lodowisko-a.example/cennik/", @page_text)}
      "https://lodowisko-b.example/cennik" -> {:ok, %{html_page("https://lodowisko-b.example/cennik", "") | status: 503}}
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :competitor_prices} ->
      {:ok,
       %{
         "offers" => [
           %{"name" => "Wypożyczenie łyżew", "price" => "15 zł", "quote" => "Wypożyczenie łyżew: 15 zł za godzinę"},
           %{"name" => "Karnet", "price" => "120 zł", "quote" => "Karnet miesięczny 120 zł"}
         ]
       }, Decimal.new("0.004")}
    end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert %PriceCheck{status: :done, error: nil, competitor_pages: [found, unreadable]} =
             PriceChecks.get_for_niche(price_check.niche)

    assert %CompetitorPage{outcome: :prices_found, read_url: "https://lodowisko-a.example/cennik/"} = found

    assert [%CompetitorOffer{name: "Wypożyczenie łyżew", price: "15 zł", quote: "Wypożyczenie łyżew: 15 zł za godzinę"}] =
             found.offers

    assert %CompetitorPage{outcome: :unreadable, read_url: nil, offers: []} = unreadable
    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.004"))
    niche_id = price_check.cluster_id
    assert_received {:price_check_updated, ^niche_id}
  end

  test "the model gets the page text with the Niche's name and Phrases, and the run's Steps stay as they were" do
    %{run: run, price_check: price_check} =
      checking(%{domains: ["lodowisko-a.example"], niche_name: "Łyżwy w Gdańsku", phrase: "wypożyczalnia łyżew"})

    test_pid = self()
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_pid, {:request, request})
      {:ok, %{"offers" => []}, Decimal.new(0)}
    end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert_received {:request, %{task: :competitor_prices, input: input, prompt: prompt, schema: schema}}

    assert input == %{
             niche_name: "Łyżwy w Gdańsku",
             phrases: ["wypożyczalnia łyżew"],
             url: "https://lodowisko-a.example/cennik",
             text: @page_text
           }

    assert prompt =~ @page_text
    assert prompt =~ "Łyżwy w Gdańsku"
    assert prompt =~ "written in English for the owner of this tool"
    assert prompt =~ "the price exactly as it is written"
    assert schema.properties.offers.items.required == ["name", "price", "quote"]
    assert [%CompetitorPage{outcome: :no_prices}] = PriceChecks.get_for_niche(price_check.niche).competitor_pages
    assert %Run{status: :awaiting_choice} = Repo.get!(Run, run.id)

    assert run_step_statuses(run) == 1..7 |> Map.new(&{&1, :done}) |> Map.put(8, :waiting)
  end

  test "a page without visible text has no prices and is not sent to the model" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, "")} end)
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :no_prices, offers: []}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  test "checking again replays the stored page and answer instead of fetching or paying twice" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    expect(Dirmoon.WebPageMock, :fetch, 1, fn url -> {:ok, html_page(url, @page_text)} end)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok, %{"offers" => [%{"name" => "Ostrzenie", "price" => "20 zł", "quote" => "Ostrzenie łyżew 20 zł"}]},
       Decimal.new("0.003")}
    end)

    :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})
    Repo.update_all(PriceCheck, set: [status: :checking])
    Repo.update_all(CompetitorPage, set: [outcome: :waiting, offers: []])

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :prices_found, offers: [%CompetitorOffer{price: "20 zł"}]}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages

    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.003"))
  end

  test "a model error is retried, and the pages read before it keep their outcome" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example", "lodowisko-b.example"]})

    stub(Dirmoon.WebPageMock, :fetch, fn
      "https://lodowisko-a.example/cennik" -> {:error, "the page could not be read"}
      url -> {:ok, html_page(url, @page_text)}
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, "OpenAI: HTTP 500"} end)

    assert {:error, "OpenAI: HTTP 500"} = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert %PriceCheck{status: :checking, competitor_pages: [unreadable, waiting]} =
             PriceChecks.get_for_niche(price_check.niche)

    assert unreadable.outcome == :unreadable
    assert waiting.outcome == :waiting
  end

  test "on the last attempt a model error fails the check with its reason" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    PriceChecks.subscribe(run)
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, "OpenAI: HTTP 500"} end)

    assert {:cancel, "OpenAI: HTTP 500"} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "OpenAI: HTTP 500"} = PriceChecks.get_for_niche(price_check.niche)
    assert_received {:price_check_updated, _niche_id}
  end

  test "without an LLM key the check fails at once and says the key is missing" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert %PriceCheck{status: :failed, error: "No OpenAI API key"} = PriceChecks.get_for_niche(price_check.niche)
  end

  test "an answer without a list of offers is not stored and fails the check on the last attempt" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"offers" => "15 zł"}, Decimal.new("0.002")} end)

    assert {:cancel, "The model returned no list of offers"} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "The model returned no list of offers"} =
             PriceChecks.get_for_niche(price_check.niche)

    refute ApiRequest |> where(service: "llm") |> Repo.exists?()
  end

  test "an unexpected crash fails the check on the last attempt with a readable reason" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch, fn _url -> raise ArgumentError, "zepsuty adres" end)

    assert {:cancel, %ArgumentError{}} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "Unexpected error: zepsuty adres"} =
             PriceChecks.get_for_niche(price_check.niche)
  end

  test "a check that is done or gone is left alone" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    price_check |> Ecto.Changeset.change(status: :done) |> Repo.update!()
    expect(Dirmoon.WebPageMock, :fetch, 0, fn _url -> {:error, "nie wolno"} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})
    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id + 1_000_000})
    assert %PriceCheck{status: :done} = Repo.get!(PriceCheck, price_check.id)
  end

  test "each page read keeps the facts that compare it with the site's page, and the ledger keeps its text, not its HTML" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})

    html =
      "<html><head><title>Lodowisko A</title></head><body><h1>Cennik</h1><h2>Łyżwy</h2><p>#{@page_text}</p></body></html>"

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      {:ok, %{url: url, status: 200, redirects: [], content_type: "text/html", body: html}}
    end)

    stub(Dirmoon.LLMMock, :structured, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{facts: facts}] = PriceChecks.get_for_niche(price_check.niche).competitor_pages

    assert %{
             "main_heading_count" => 1,
             "sub_heading_count" => 1,
             "title_length" => 11,
             "structured_data_types" => [],
             "images" => 0,
             "ways_to_act" => %{"phone_links" => 0}
           } = facts

    assert facts["word_count"] > 0

    assert [%ApiRequest{response: %{"text" => text, "url" => _read_url, "facts" => ^facts} = response}] =
             ApiRequest |> where(run_id: ^run.id, service: "web_page") |> Repo.all()

    assert text =~ "Wypożyczenie łyżew"
    refute response |> Jason.encode!() |> String.contains?("<h1>")
  end

  test "a plain-text page is read for prices and has no facts to compare" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      {:ok, %{url: url, status: 200, redirects: [], content_type: "text/plain", body: @page_text}}
    end)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :no_prices, facts: nil}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  test "a page that is not HTML or plain text is unreadable, as before" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})

    stub(Dirmoon.WebPageMock, :fetch, fn url ->
      {:ok, %{url: url, status: 200, redirects: [], content_type: "application/pdf", body: ""}}
    end)

    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :unreadable, facts: nil}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  test "a page read before the facts were kept is replayed from the ledger, and its facts stay empty" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})

    {:ok, _stored} =
      Ledger.fetch(
        run,
        %{service: "web_page", operation: "fetch_text", request: %{url: "https://lodowisko-a.example/cennik"}},
        fn -> {:ok, %{"text" => @page_text, "url" => "https://lodowisko-a.example/cennik/"}, Decimal.new(0)} end
      )

    expect(Dirmoon.WebPageMock, :fetch, 0, fn _url -> {:error, "not called"} end)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{input: %{text: @page_text}} ->
      {:ok, %{"offers" => [%{"name" => "Ostrzenie", "price" => "20 zł", "quote" => "Ostrzenie łyżew 20 zł"}]},
       Decimal.new("0.003")}
    end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :prices_found, read_url: "https://lodowisko-a.example/cennik/", facts: nil}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  test "for an Existing Site one request counts the sites linking to every competitor's domain, paid once" do
    %{run: run, price_check: price_check} =
      checking(%{domains: ["lodowisko-b.example", "lodowisko-a.example"], mode: :existing_site})

    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
    stub(Dirmoon.LLMMock, :structured, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    expect(Dirmoon.DataForSEOMock, :linking_sites, 1, fn %{domains: domains} ->
      assert domains == ["lodowisko-a.example", "lodowisko-b.example"]

      {:ok,
       %{
         rows: [%{domain: "lodowisko-a.example", linking_sites: 31}],
         raw: %{"tasks" => []},
         cost: Decimal.new("0.024072")
       }}
    end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})
    Repo.update_all(PriceCheck, set: [status: :checking])
    Repo.update_all(CompetitorPage, set: [outcome: :waiting, linking_sites: nil])
    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{domain: "lodowisko-b.example", linking_sites: nil}, %CompetitorPage{linking_sites: 31}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages

    assert Decimal.equal?(Research.run_cost(run), Decimal.new("0.024072"))
  end

  test "linking sites refused, unavailable, failed or crashing never fail the check and leave the counts empty" do
    failures = [
      fn _request ->
        {:error, {:linking_sites_unavailable, %{message: "DataForSEO: Access denied.", raw: %{}, cost: 0}}}
      end,
      fn _request -> {:error, :not_in_demo_data} end,
      fn _request -> {:error, :data_for_seo_not_configured} end,
      fn _request -> {:error, "DataForSEO: HTTP 500"} end,
      fn _request -> raise "the link index broke" end,
      fn _request -> exit(:link_index_gone) end,
      fn _request -> throw(:link_index_gave_up) end
    ]

    for failure <- failures do
      %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"], mode: :existing_site})
      stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
      stub(Dirmoon.LLMMock, :structured, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)
      expect(Dirmoon.DataForSEOMock, :linking_sites, 1, failure)

      assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

      assert %PriceCheck{status: :done, competitor_pages: [%CompetitorPage{outcome: :no_prices, linking_sites: nil}]} =
               PriceChecks.get_for_niche(price_check.niche)
    end
  end

  test "a New Idea run has no site to compare, so its check buys no linking sites" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"], mode: :new_idea})
    stub(Dirmoon.WebPageMock, :fetch, fn url -> {:ok, html_page(url, @page_text)} end)
    stub(Dirmoon.LLMMock, :structured, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)
    expect(Dirmoon.DataForSEOMock, :linking_sites, 0, fn _request -> {:error, :not_in_demo_data} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{linking_sites: nil}] = PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  defp html_page(url, text),
    do: %{
      url: url,
      status: 200,
      redirects: [],
      content_type: "text/html",
      body: "<html><body><p>#{text}</p></body></html>"
    }

  defp run_step_statuses(run) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run.id)
    |> select([run_step: run_step], {run_step.number, run_step.status})
    |> Repo.all()
    |> Map.new()
  end

  defp checking(%{domains: domains} = attrs) do
    run =
      insert(:run,
        mode: Map.get(attrs, :mode, :new_idea),
        domain: if(Map.get(attrs, :mode) == :existing_site, do: "lodowisko-moje.example"),
        status: :awaiting_choice,
        steps: build_run_steps(Map.new(1..7, &{&1, :done}))
      )

    niche = insert(:niche, run: run, name: Map.get(attrs, :niche_name, "Nisza testowa cen"))
    phrase = insert(:phrase, phrase: Map.get(attrs, :phrase, unique_phrase_text("fraza cen")))
    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
    price_check = insert(:price_check, run: run, niche: niche)

    domains
    |> Enum.with_index(1)
    |> Enum.each(fn {domain, position} ->
      insert(:competitor_page, price_check: price_check, domain: domain, google_position: position)
    end)

    %{run: run, price_check: Repo.preload(price_check, :niche, force: true)}
  end
end
