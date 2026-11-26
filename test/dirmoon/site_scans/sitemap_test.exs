defmodule Dirmoon.SiteScans.SitemapTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Sitemap

  test "a sitemap lists the addresses of its pages" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
      <url><loc> https://hotel-testowy.example/ </loc><lastmod>2026-01-01</lastmod></url>
      <url>
        <loc>https://hotel-testowy.example/pokoje?a=1&amp;b=2</loc>
        <image:image><image:loc>https://hotel-testowy.example/zdjecie.jpg</image:loc></image:image>
      </url>
    </urlset>
    """

    assert Sitemap.urls(xml) == %{
             page_urls: ["https://hotel-testowy.example/", "https://hotel-testowy.example/pokoje?a=1&b=2"],
             sitemap_urls: []
           }
  end

  test "a sitemap index lists its nested sitemaps apart from pages" do
    xml = """
    <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <sitemap><loc>https://hotel-testowy.example/strony.xml</loc></sitemap>
      <sitemap><loc>https://hotel-testowy.example/wpisy.xml</loc></sitemap>
    </sitemapindex>
    """

    assert Sitemap.urls(xml) == %{
             page_urls: [],
             sitemap_urls: ["https://hotel-testowy.example/strony.xml", "https://hotel-testowy.example/wpisy.xml"]
           }
  end

  test "addresses that are not web addresses are left out" do
    xml =
      "<urlset><url><loc>ftp://hotel-testowy.example/x</loc></url><url><loc>/wzgledny</loc></url><url><loc></loc></url></urlset>"

    assert Sitemap.urls(xml) == %{page_urls: [], sitemap_urls: []}
  end

  test "an address that can't be parsed is left out" do
    xml =
      "<urlset><url><loc>https://a.example/strona z spacją</loc></url><url><loc>https://a.example/</loc></url></urlset>"

    assert %{page_urls: ["https://a.example/"]} = Sitemap.urls(xml)
  end

  test "the same address listed twice counts once" do
    xml = "<urlset><url><loc>https://a.example/</loc></url><url><loc>https://a.example/</loc></url></urlset>"

    assert %{page_urls: ["https://a.example/"]} = Sitemap.urls(xml)
  end

  test "something that is not a sitemap lists nothing" do
    assert Sitemap.urls("<html><body><h1>Nie znaleziono</h1></body></html>") == %{page_urls: [], sitemap_urls: []}
    assert Sitemap.urls(:binary.copy(<<0, 255, ?<, ?>>>, 1_000)) == %{page_urls: [], sitemap_urls: []}
    assert Sitemap.urls("") == %{page_urls: [], sitemap_urls: []}
  end

  test "broken XML lists the addresses that can still be read" do
    xml = "<urlset><url><loc>https://a.example/1</loc><url><loc>https://a.example/2"

    assert %{page_urls: ["https://a.example/1", "https://a.example/2"]} = Sitemap.urls(xml)
  end

  test "a huge sitemap lists at most two thousand pages and fifty nested sitemaps" do
    pages = Enum.map_join(1..30_000, &"<url><loc>https://a.example/#{&1}</loc></url>")
    sitemaps = Enum.map_join(1..1_000, &"<sitemap><loc>https://a.example/s#{&1}.xml</loc></sitemap>")

    %{page_urls: page_urls} = Sitemap.urls("<urlset>#{pages}</urlset>")
    %{sitemap_urls: sitemap_urls} = Sitemap.urls("<sitemapindex>#{sitemaps}</sitemapindex>")

    assert Enum.count(page_urls) == 2_000
    assert hd(page_urls) == "https://a.example/1"
    assert Enum.count(sitemap_urls) == 50
  end

  test "an address longer than 2,048 bytes is left out" do
    too_long = "https://a.example/" <> String.duplicate("a", 2_048)
    xml = "<urlset><url><loc>#{too_long}</loc></url><url><loc>https://a.example/</loc></url></urlset>"

    assert %{page_urls: ["https://a.example/"]} = Sitemap.urls(xml)
  end

  test "an address with bytes that are not UTF-8 is left out and a NUL character is dropped from it" do
    xml =
      "<urlset><url><loc>https://a.example/k\xF3d</loc></url><url><loc>https://a.example/a\u0000b</loc></url>" <>
        "<url><loc>https://a.example/</loc></url></urlset>"

    assert %{page_urls: ["https://a.example/ab", "https://a.example/"]} = Sitemap.urls(xml)
  end
end
