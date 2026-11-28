defmodule DirmoonWeb.OfferDisplayTest do
  use ExUnit.Case, async: true

  alias DirmoonWeb.OfferDisplay

  test "one research shows the single price, paid once, and that it never expires" do
    offer = offer(%{single_price: "12"})

    assert OfferDisplay.single_research(offer) == %{
             name: "One research",
             price: "$12",
             price_note: "paid once",
             details: "One research, to try dirmoon. It never expires."
           }
  end

  test "the monthly plan shows the monthly price and its researches a month, which don't carry over" do
    offer = offer(%{monthly_price: "59", monthly_researches: 8})

    assert OfferDisplay.monthly_plan(offer) == %{
             name: "Monthly plan",
             price: "$59",
             price_note: "a month",
             details: "8 researches a month. Researches you don't use in a month don't carry over."
           }
  end

  test "a monthly plan of one research a month says it in the singular" do
    offer = offer(%{monthly_researches: 1})

    assert OfferDisplay.monthly_plan(offer).details ==
             "1 research a month. A research you don't use in a month doesn't carry over."
  end

  test "a research includes up to its caps of briefs and competitor price checks, and the site scan" do
    offer = offer(%{briefs_per_research: 5, price_checks_per_research: 4})

    assert OfferDisplay.research_includes(offer) == [
             "Up to 5 briefs: the plan and the text for one page each",
             "Up to 4 competitor price checks",
             "For an existing site, a scan of your site"
           ]
  end

  test "caps of one brief and one price check are said in the singular" do
    offer = offer(%{briefs_per_research: 1, price_checks_per_research: 1})

    assert OfferDisplay.research_includes(offer) == [
             "Up to 1 brief: the plan and the text for one page",
             "Up to 1 competitor price check",
             "For an existing site, a scan of your site"
           ]
  end

  defp offer(overrides) do
    Map.merge(
      %{
        single_price: "10",
        monthly_price: "49",
        monthly_researches: 10,
        briefs_per_research: 3,
        price_checks_per_research: 3
      },
      overrides
    )
  end
end
