defmodule DirmoonWeb.OfferDisplay do
  @moduledoc """
  The words for the two ways to pay and for what a research includes, built
  from `Dirmoon.Billing.offer/0`. The landing page's pricing section and the
  plan screen both render them, each in its own markup, so the two screens
  never say different things about the offer.
  """

  alias Dirmoon.Format

  @research_forms %{one: "research", other: "researches"}
  @brief_forms %{one: "brief", other: "briefs"}
  @brief_explanation_forms %{one: "the plan and the text for one page", other: "the plan and the text for one page each"}
  @price_check_forms %{one: "competitor price check", other: "competitor price checks"}

  @doc """
  The one-off Single Research: its name, price, price note and one line.
  """
  def single_research(%{single_price: price}) do
    %{
      name: "One research",
      price: usd(price),
      price_note: "paid once",
      details: "One research, to try dirmoon. It never expires."
    }
  end

  @doc """
  The Subscription: its name, price, price note and its researches a month,
  which don't carry over.
  """
  def monthly_plan(%{monthly_price: price, monthly_researches: researches}) do
    %{
      name: "Monthly plan",
      price: usd(price),
      price_note: "a month",
      details: "#{researches} #{Format.plural(researches, @research_forms)} a month. #{carry_over_sentence(researches)}"
    }
  end

  @doc """
  What one research includes: its Research Caps and, for an existing site,
  the Site Scan.
  """
  def research_includes(%{briefs_per_research: briefs, price_checks_per_research: price_checks}) do
    [
      "Up to #{briefs} #{Format.plural(briefs, @brief_forms)}: #{Format.plural(briefs, @brief_explanation_forms)}",
      "Up to #{price_checks} #{Format.plural(price_checks, @price_check_forms)}",
      "For an existing site, a scan of your site"
    ]
  end

  defp usd(price), do: "$" <> price

  defp carry_over_sentence(1), do: "A research you don't use in a month doesn't carry over."
  defp carry_over_sentence(_researches), do: "Researches you don't use in a month don't carry over."
end
