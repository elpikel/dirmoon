defmodule DirmoonWeb.SearchEngineFilesTest do
  use DirmoonWeb.ConnCase, async: true

  test "robots.txt lets search engines read the public site, keeps them out of the app and names the sitemap",
       %{conn: conn} do
    lines = conn |> get("/robots.txt") |> response(200) |> String.split("\n", trim: true)
    rules = Enum.reject(lines, &String.starts_with?(&1, "#"))

    assert rules == ["User-agent: *", "Disallow: /app/", "Sitemap: https://dirmoon.com/sitemap.xml"]
  end

  test "the sitemap lists the landing page, the only page meant for search results", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "xml"

    locations = conn |> response(200) |> LazyHTML.from_fragment() |> LazyHTML.query("urlset url loc")

    assert Enum.map(locations, &LazyHTML.text/1) == ["https://dirmoon.com/"]
  end
end
