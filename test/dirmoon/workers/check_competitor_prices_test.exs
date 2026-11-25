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
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.CheckCompetitorPrices

  @page_text "Cennik Wypożyczenie łyżew: 15 zł za godzinę. Ostrzenie łyżew 20 zł."

  test "each page's verified prices are stored, an unreadable page is noted and the check is done" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example", "lodowisko-b.example"]})
    PriceChecks.subscribe(run)

    expect(Dirmoon.WebPageMock, :fetch_text, 2, fn
      "https://lodowisko-a.example/cennik" -> {:ok, %{text: @page_text, url: "https://lodowisko-a.example/cennik/"}}
      "https://lodowisko-b.example/cennik" -> {:error, "HTTP 503"}
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
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @page_text, url: url}} end)

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
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: "", url: url}} end)
    expect(Dirmoon.LLMMock, :structured, 0, fn _request -> {:ok, %{"offers" => []}, Decimal.new(0)} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert [%CompetitorPage{outcome: :no_prices, offers: []}] =
             PriceChecks.get_for_niche(price_check.niche).competitor_pages
  end

  test "checking again replays the stored page and answer instead of fetching or paying twice" do
    %{run: run, price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    expect(Dirmoon.WebPageMock, :fetch_text, 1, fn url -> {:ok, %{text: @page_text, url: url}} end)

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

    stub(Dirmoon.WebPageMock, :fetch_text, fn
      "https://lodowisko-a.example/cennik" -> {:error, "HTTP 404"}
      url -> {:ok, %{text: @page_text, url: url}}
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
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @page_text, url: url}} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, "OpenAI: HTTP 500"} end)

    assert {:cancel, "OpenAI: HTTP 500"} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "OpenAI: HTTP 500"} = PriceChecks.get_for_niche(price_check.niche)
    assert_received {:price_check_updated, _niche_id}
  end

  test "without an LLM key the check fails at once and says the key is missing" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @page_text, url: url}} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})

    assert %PriceCheck{status: :failed, error: "No OpenAI API key"} = PriceChecks.get_for_niche(price_check.niche)
  end

  test "an answer without a list of offers is not stored and fails the check on the last attempt" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch_text, fn url -> {:ok, %{text: @page_text, url: url}} end)
    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"offers" => "15 zł"}, Decimal.new("0.002")} end)

    assert {:cancel, "The model returned no list of offers"} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "The model returned no list of offers"} =
             PriceChecks.get_for_niche(price_check.niche)

    refute ApiRequest |> where(service: "llm") |> Repo.exists?()
  end

  test "an unexpected crash fails the check on the last attempt with a readable reason" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    stub(Dirmoon.WebPageMock, :fetch_text, fn _url -> raise ArgumentError, "zepsuty adres" end)

    assert {:cancel, %ArgumentError{}} =
             perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id}, attempt: 3)

    assert %PriceCheck{status: :failed, error: "Unexpected error: zepsuty adres"} =
             PriceChecks.get_for_niche(price_check.niche)
  end

  test "a check that is done or gone is left alone" do
    %{price_check: price_check} = checking(%{domains: ["lodowisko-a.example"]})
    price_check |> Ecto.Changeset.change(status: :done) |> Repo.update!()
    expect(Dirmoon.WebPageMock, :fetch_text, 0, fn _url -> {:error, "nie wolno"} end)

    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id})
    assert :ok = perform_job(CheckCompetitorPrices, %{price_check_id: price_check.id + 1_000_000})
    assert %PriceCheck{status: :done} = Repo.get!(PriceCheck, price_check.id)
  end

  defp run_step_statuses(run) do
    RunStep
    |> from(as: :run_step)
    |> where([run_step: run_step], run_step.run_id == ^run.id)
    |> select([run_step: run_step], {run_step.number, run_step.status})
    |> Repo.all()
    |> Map.new()
  end

  defp checking(%{domains: domains} = attrs) do
    run = insert(:run, status: :awaiting_choice, steps: build_run_steps(Map.new(1..7, &{&1, :done})))
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
