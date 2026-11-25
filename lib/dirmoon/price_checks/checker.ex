defmodule Dirmoon.PriceChecks.Checker do
  @moduledoc """
  Reads a Price Check's waiting Competitor Pages one by one:

    * the page is read through the web page seam (`Dirmoon.WebPage`), via
      the run's ledger at no cost, so a page already read is replayed;
    * a page that could not be opened is `:unreadable`, and the check goes
      on with the next page;
    * the LLM lists the offers it finds in the page text, through the
      run's ledger, so the request is paid once and counts in the run's API
      Cost; a blank page is not sent;
    * only offers the page text backs are kept
      (`Dirmoon.PriceChecks.CompetitorOffer.verified/2`), and a page without
      any is `:no_prices`.

  Each page's outcome is stored as soon as it is known, so a retry goes on
  where the last attempt stopped.

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
  alias Dirmoon.WebPage

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

  defp read_page(page, %{price_check: price_check} = context) do
    case Ledger.fetch(price_check.run, %{service: "web_page", operation: "fetch_text", request: %{url: page.url}}, fn ->
           fetch_text(page.url)
         end) do
      {:ok, %{"text" => text, "url" => read_url}} ->
        find_offers(page, Map.merge(context, %{text: text, read_url: read_url}))

      {:error, _reason} ->
        {:ok, %{outcome: :unreadable}}
    end
  end

  defp fetch_text(url) do
    with {:ok, %{text: text, url: read_url}} <- WebPage.fetch_text(url) do
      {:ok, %{"text" => text, "url" => read_url}, Decimal.new(0)}
    end
  end

  defp find_offers(_page, %{text: "", read_url: read_url}), do: {:ok, %{outcome: :no_prices, read_url: read_url}}

  defp find_offers(%CompetitorPage{}, %{price_check: price_check, text: text, read_url: read_url} = context) do
    request = offers_request(%{niche_name: price_check.niche.name, phrases: context.phrases, url: read_url, text: text})

    with {:ok, %{"offers" => answer_offers}} <-
           Ledger.fetch(price_check.run, %{service: "llm", operation: "competitor_prices", request: request}, fn ->
             listed_offers(request)
           end) do
      offers = CompetitorOffer.verified(answer_offers, %{page_text: text, limit: @offer_limit})
      outcome = if offers == [], do: :no_prices, else: :prices_found
      {:ok, %{outcome: outcome, offers: offers, read_url: read_url}}
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
