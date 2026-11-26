defmodule Dirmoon.PriceChecks.Checker do
  @moduledoc """
  Reads a Price Check's waiting Competitor Pages one by one:

    * the page is read once, raw, through the web page seam
      (`Dirmoon.WebPage.fetch/1`), via the run's ledger at no cost, so a
      page already read is replayed. The ledger keeps what the price lookup
      needs, not the HTML: the visible text and the address read
      (`Dirmoon.WebPage.text_page/1`, as `fetch_text/1` gives them, under
      the operation `"fetch_text"` as before) and, for an HTML page, the
      Page Facts that compare it with the site's own page
      (`Dirmoon.WebPage.PageFacts.comparison/1`), stored on the Competitor
      Page. A page read before the facts were kept is replayed without
      them, so its facts stay nil;
    * a page that could not be opened (no answer, a status other than 200,
      not HTML or plain text) is `:unreadable`, and the check goes on with
      the next page;
    * the LLM lists the offers it finds in the page text, through the
      run's ledger, so the request is paid once and counts in the run's API
      Cost; a blank page is not sent;
    * only offers the page text backs are kept
      (`Dirmoon.PriceChecks.CompetitorOffer.verified/2`), and a page without
      any is `:no_prices`.

  Each page's outcome is stored as soon as it is known, so a retry goes on
  where the last attempt stopped.

  For an Existing Site run, before the pages are read, one request asks how
  many other sites link to each Competitor Page's domain
  (`Dirmoon.SiteScans.LinkingSites`, through the run's ledger, so a retry
  replays it), for the comparison with the site. It never fails the check:
  a refusal, an error or a crash leaves the counts nil. A New Idea run has
  no site to compare, so it buys none.

  Prices and quotes stay exactly as the page writes them, in its language;
  the model names each offer in English for the owner.
  """

  alias Dirmoon.LLM
  alias Dirmoon.Phrases
  alias Dirmoon.PriceChecks
  alias Dirmoon.PriceChecks.CompetitorOffer
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans.LinkingSites
  alias Dirmoon.WebPage
  alias Dirmoon.WebPage.PageFacts

  @phrase_limit 10
  @offer_limit 15
  @malformed_answer_error "The model returned no list of offers"

  @system """
  You list the prices from the text of a business's web page. You give only prices written in that text, \
  exactly as they are written; you never guess, convert or add anything. \
  You answer only in JSON that matches the schema.\
  """

  @schema %{
    type: "object",
    properties: %{
      offers: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            name: %{type: "string"},
            price: %{type: "string"},
            quote: %{type: "string"}
          },
          required: ["name", "price", "quote"]
        }
      }
    },
    required: ["offers"]
  }

  @doc """
  Reads every waiting page of the check (loaded by
  `Dirmoon.PriceChecks.get_checking/1`, with its run and Niche).

  Returns `:ok` when every page has an outcome, or the LLM's
  `{:error, reason}` (or `{:error, "#{@malformed_answer_error}"}`); pages
  read before the error keep their outcome.
  """
  def check(%PriceCheck{competitor_pages: pages} = price_check) do
    record_linking_sites(price_check)
    context = %{price_check: price_check, phrases: phrase_texts(price_check)}

    pages
    |> Enum.filter(&(&1.outcome == :waiting))
    |> Enum.reduce_while(:ok, fn page, :ok ->
      case read_page(page, context) do
        {:ok, reading} ->
          PriceChecks.record_page(price_check, page, reading)
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp record_linking_sites(%PriceCheck{run: %Run{mode: :existing_site} = run, competitor_pages: pages} = price_check) do
    case LinkingSites.count(run, Enum.map(pages, & &1.domain)) do
      {:ok, counts} -> PriceChecks.record_linking_sites(price_check, counts)
      {:error, _unavailable_or_failed} -> :ok
    end
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp record_linking_sites(%PriceCheck{}), do: :ok

  defp read_page(page, %{price_check: price_check} = context) do
    case Ledger.fetch(price_check.run, %{service: "web_page", operation: "fetch_text", request: %{url: page.url}}, fn ->
           read_competitor_page(page.url)
         end) do
      {:ok, %{"text" => text, "url" => read_url} = answer} ->
        find_offers(page, Map.merge(context, %{text: text, read_url: read_url, facts: answer["facts"]}))

      {:error, _reason} ->
        {:ok, %{outcome: :unreadable}}
    end
  end

  defp read_competitor_page(url) do
    with {:ok, raw_page} <- WebPage.fetch(url),
         {:ok, %{text: text, url: read_url}} <- WebPage.text_page(raw_page) do
      {:ok, %{"text" => text, "url" => read_url, "facts" => comparison_facts(raw_page)}, Decimal.new(0)}
    end
  end

  defp comparison_facts(%{body: body, url: url} = raw_page) do
    if WebPage.html?(raw_page), do: body |> PageFacts.from_html(url) |> PageFacts.comparison()
  end

  defp find_offers(_page, %{text: "", read_url: read_url, facts: facts}),
    do: {:ok, %{outcome: :no_prices, read_url: read_url, facts: facts}}

  defp find_offers(%CompetitorPage{}, %{price_check: price_check, text: text, read_url: read_url} = context) do
    request = offers_request(%{niche_name: price_check.niche.name, phrases: context.phrases, url: read_url, text: text})

    with {:ok, %{"offers" => answer_offers}} <-
           Ledger.fetch(price_check.run, %{service: "llm", operation: "competitor_prices", request: request}, fn ->
             listed_offers(request)
           end) do
      offers = CompetitorOffer.verified(answer_offers, %{page_text: text, limit: @offer_limit})
      outcome = if offers == [], do: :no_prices, else: :prices_found
      {:ok, %{outcome: outcome, offers: offers, read_url: read_url, facts: context.facts}}
    end
  end

  defp listed_offers(request) do
    case LLM.structured(request) do
      {:ok, %{"offers" => offers} = answer, cost} when is_list(offers) -> {:ok, answer, cost}
      {:ok, _malformed, _cost} -> {:error, @malformed_answer_error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp offers_request(input) do
    %{task: :competitor_prices, system: @system, prompt: prompt(input), schema: @schema, input: input}
  end

  defp prompt(%{niche_name: niche_name, phrases: phrases, url: url, text: text}) do
    Enum.join(
      [
        "Niche: #{niche_name}",
        "Phrases customers type: #{Enum.join(phrases, ", ")}",
        "Page address: #{url}",
        "List the offers with prices given in the page text. For each give: the name of the service or product, " <>
          "written in English for the owner of this tool; the price exactly as it is written (with its currency " <>
          "and unit, if any), in the page's own language; and a quote: a fragment of the page text, copied " <>
          "character for character in the page's own language, that contains this price. " <>
          "If the page gives no prices, return an empty list.",
        "Page text:\n#{text}"
      ],
      "\n\n"
    )
  end

  defp phrase_texts(%PriceCheck{run: run, cluster_id: niche_id}) do
    run
    |> Phrases.list_for_run(%{niche_id: niche_id, limit: @phrase_limit})
    |> Enum.map(& &1.phrase.phrase)
  end
end
