defmodule Dirmoon.SiteScans.Sitemap do
  @moduledoc """
  Reads a sitemap's addresses. Pure: no I/O.

  `urls/1` answers the page addresses of a `<urlset>` (`page_urls`) and the
  nested sitemap addresses of a `<sitemapindex>` (`sitemap_urls`), each
  trimmed, de-duplicated and kept only when it is a web address
  (`Dirmoon.WebPage.WebAddress`: `http` or `https`, at most 2,048 bytes). The document is parsed by the same forgiving parser as a
  page (`Dirmoon.WebPage.HtmlDocument`), so broken XML gives the addresses
  that can still be read and anything else gives none, in time linear in
  its size. At most 2,000 pages and 50 nested sitemaps are kept. The
  document is read as text a jsonb column can hold
  (`Dirmoon.JsonSafe.text/1`), so an address with bytes that are not UTF-8
  is no web address and is left out, and NUL characters are dropped.
  """

  alias Dirmoon.JsonSafe
  alias Dirmoon.WebPage.HtmlDocument
  alias Dirmoon.WebPage.WebAddress

  @max_page_urls 2_000
  @max_sitemap_urls 50

  @doc "The page and nested sitemap addresses listed in `xml`."
  @spec urls(String.t()) :: %{page_urls: [String.t()], sitemap_urls: [String.t()]}
  def urls(xml) when is_binary(xml) do
    document = xml |> JsonSafe.text() |> HtmlDocument.parse()

    %{
      page_urls: addresses(document, %{selector: "urlset url > loc", limit: @max_page_urls}),
      sitemap_urls: addresses(document, %{selector: "sitemapindex sitemap > loc", limit: @max_sitemap_urls})
    }
  end

  defp addresses(document, %{selector: selector, limit: limit}) do
    document
    |> LazyHTML.query(selector)
    |> Stream.map(&(&1 |> LazyHTML.text() |> String.trim()))
    |> Stream.filter(&WebAddress.acceptable?/1)
    |> Stream.uniq()
    |> Enum.take(limit)
  end
end
