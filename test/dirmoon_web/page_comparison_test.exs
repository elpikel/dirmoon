defmodule DirmoonWeb.PageComparisonTest do
  use ExUnit.Case, async: true

  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans.ScannedPage
  alias DirmoonWeb.PageComparison

  test "stored figures of an unexpected type are shown as unknown, never raw" do
    odd = %{
      "word_count" => "800",
      "main_heading_count" => 1,
      "sub_heading_count" => nil,
      "structured_data_types" => nil,
      "ways_to_act" => "phone"
    }

    assert %{competitors: [row]} = build([competitor(%{facts: odd, linking_sites: -1})])

    assert %{
             words: "—",
             headings: "—",
             structured_data: "No",
             types: nil,
             contact: "—",
             linking_sites: "—"
           } = row
  end

  test "a competitor's page read over http or https is linked, at the address read" do
    assert %{competitors: [%{href: "http://hotel-a.example/cennik"}, %{href: "https://hotel-b.example/"}]} =
             build([
               competitor(%{read_url: "http://hotel-a.example/cennik"}),
               competitor(%{id: 2, url: "https://hotel-b.example/"})
             ])
  end

  test "a way to contact that is not a whole count is not counted" do
    ways = %{"phone_links" => "2", "email_links" => nil, "forms" => 1}

    assert %{competitors: [%{contact: "Form"}]} =
             build([competitor(%{facts: %{"ways_to_act" => ways, "structured_data_types" => ["Offer"]}})])
  end

  test "the site's page is compared on its own Page Facts, and a price on it is never known" do
    page = %ScannedPage{url: "https://strona-testowa.example/", facts: %{"word_count" => 12, "title" => "Start"}}
    site = %{scan_status: :done, matched?: true, pages: [page], linking_sites: nil}

    assert %{site: %{state: :page, words: "12", states_price: "—", note: nil, message: nil}} =
             PageComparison.build(%{run: existing_site_run(), price_check: price_check([competitor(%{})]), site: site})
  end

  defp build(pages), do: PageComparison.build(%{run: existing_site_run(), price_check: price_check(pages), site: nil})

  defp existing_site_run, do: %Run{mode: :existing_site}

  defp price_check(pages), do: %PriceCheck{status: :done, competitor_pages: pages}

  defp competitor(attrs) do
    struct(
      %CompetitorPage{id: 1, domain: "hotel-a.example", url: "https://hotel-a.example/", outcome: :no_prices},
      attrs
    )
  end
end
