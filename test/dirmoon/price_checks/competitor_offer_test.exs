defmodule Dirmoon.PriceChecks.CompetitorOfferTest do
  use ExUnit.Case, async: true

  alias Dirmoon.PriceChecks.CompetitorOffer

  @page_text "Cennik Wypożyczenie łyżew: 15 zł za godzinę. Ostrzenie łyżew 20 zł."

  test "an offer whose quote is in the page and whose price is in its quote is kept, trimmed" do
    offers = [
      %{"name" => " Wypożyczenie łyżew ", "price" => "15 zł", "quote" => "Wypożyczenie  łyżew:\n15 zł za godzinę"}
    ]

    assert CompetitorOffer.verified(offers, %{page_text: @page_text, limit: 10}) == [
             %CompetitorOffer{name: "Wypożyczenie łyżew", price: "15 zł", quote: "Wypożyczenie łyżew: 15 zł za godzinę"}
           ]
  end

  test "an offer whose quote is not on the page is dropped" do
    offers = [%{"name" => "Karnet", "price" => "100 zł", "quote" => "Karnet miesięczny 100 zł"}]

    assert CompetitorOffer.verified(offers, %{page_text: @page_text, limit: 10}) == []
  end

  test "an offer whose price is not inside its quote is dropped" do
    offers = [%{"name" => "Ostrzenie", "price" => "25 zł", "quote" => "Ostrzenie łyżew 20 zł"}]

    assert CompetitorOffer.verified(offers, %{page_text: @page_text, limit: 10}) == []
  end

  test "blank, malformed and repeated offers are dropped and at most the limit is kept" do
    valid = %{"name" => "Ostrzenie", "price" => "20 zł", "quote" => "Ostrzenie łyżew 20 zł"}

    offers = [
      %{"name" => "", "price" => "15 zł", "quote" => "15 zł"},
      %{"name" => "Ostrzenie", "price" => 20, "quote" => "Ostrzenie łyżew 20 zł"},
      "Ostrzenie 20 zł",
      valid,
      valid,
      %{"name" => "Wypożyczenie", "price" => "15 zł", "quote" => "łyżew: 15 zł"}
    ]

    assert CompetitorOffer.verified(offers, %{page_text: @page_text, limit: 1}) == [
             %CompetitorOffer{name: "Ostrzenie", price: "20 zł", quote: "Ostrzenie łyżew 20 zł"}
           ]
  end
end
