defmodule DirmoonWeb.Controllers.Page.HomeOfferFromConfigTest do
  use DirmoonWeb.ConnCase, async: false

  test "the pricing section shows whatever prices and numbers the config holds", %{conn: conn} do
    configured = Application.fetch_env!(:dirmoon, Dirmoon.Billing)

    Application.put_env(
      :dirmoon,
      Dirmoon.Billing,
      Keyword.merge(configured,
        single_price: "12",
        monthly_price: "59",
        monthly_researches: 8,
        briefs_per_research: 5,
        price_checks_per_research: 4
      )
    )

    on_exit(fn -> Application.put_env(:dirmoon, Dirmoon.Billing, configured) end)

    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#pricing-single-research-price") |> squish() == "$12"
    assert document |> LazyHTML.query("#pricing-monthly-plan-price") |> squish() == "$59"
    assert document |> LazyHTML.query("#pricing-monthly-plan [data-part=details]") |> squish() =~ "8 researches a month."

    assert document |> LazyHTML.query("#pricing-monthly-plan-includes li") |> Enum.map(&squish/1) == [
             "Up to 5 briefs: the plan and the text for one page each",
             "Up to 4 competitor price checks",
             "For an existing site, a scan of your site"
           ]
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
