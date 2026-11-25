defmodule Dirmoon.PriceChecks.CompetitorOffer do
  @moduledoc """
  A Competitor Offer: one priced item a Competitor Page states, as the LLM
  copied it: its `name`, the `price` exactly as written on the page and a
  verbatim `quote` from the page containing that price.

  `verified/2` is the rule that keeps prices from being invented: an offer
  stays only when its quote occurs in the page text and its price occurs in
  its quote (both compared with whitespace collapsed).
  """
  use Ecto.Schema

  @whitespace ~r/\s+/u

  @primary_key false
  embedded_schema do
    field :name, :string
    field :price, :string
    field :quote, :string
  end

  @doc """
  The offers of an LLM answer (maps with string keys `"name"`, `"price"`
  and `"quote"`) that `page_text` backs, trimmed and without repeats, at
  most `limit` of them; anything else in the list is dropped.

  Returns `[%CompetitorOffer{}]`.
  """
  def verified(answer_offers, %{page_text: page_text, limit: limit}) when is_list(answer_offers) do
    page = collapse(page_text)

    answer_offers
    |> Enum.flat_map(&offer_fields/1)
    |> Enum.filter(fn offer ->
      String.contains?(page, offer["quote"]) and String.contains?(offer["quote"], offer["price"])
    end)
    |> Enum.uniq_by(&{&1["name"], &1["price"]})
    |> Enum.take(limit)
    |> Enum.map(&%__MODULE__{name: &1["name"], price: &1["price"], quote: &1["quote"]})
  end

  defp offer_fields(%{"name" => name, "price" => price, "quote" => quote})
       when is_binary(name) and is_binary(price) and is_binary(quote) do
    offer = %{"name" => collapse(name), "price" => collapse(price), "quote" => collapse(quote)}
    if Enum.any?(Map.values(offer), &(&1 == "")), do: [], else: [offer]
  end

  defp offer_fields(_malformed), do: []

  defp collapse(text), do: @whitespace |> Regex.replace(text, " ") |> String.trim()
end
