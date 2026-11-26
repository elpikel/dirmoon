defmodule Dirmoon.SiteScans.RobotsTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Robots

  test "a path the rules for every crawler disallow is not allowed" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /admin\n")

    refute Robots.allowed?(rules, "/admin/login")
    assert Robots.allowed?(rules, "/oferta")
  end

  test "the longest matching rule wins" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /oferta\nAllow: /oferta/pokoje\n")

    assert Robots.allowed?(rules, "/oferta/pokoje/1")
    refute Robots.allowed?(rules, "/oferta/cennik")
  end

  test "allow wins over disallow when both match as long" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /oferta\nAllow: /oferta\n")

    assert Robots.allowed?(rules, "/oferta")
  end

  test "a wildcard matches any characters" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /*.pdf\n")

    refute Robots.allowed?(rules, "/pliki/cennik.pdf")
    refute Robots.allowed?(rules, "/pliki/cennik.pdf?v=2")
    assert Robots.allowed?(rules, "/pliki/cennik.html")
  end

  test "a dollar sign anchors the rule at the end of the address" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /*.pdf$\nDisallow: /szukaj$\n")

    refute Robots.allowed?(rules, "/cennik.pdf")
    assert Robots.allowed?(rules, "/cennik.pdf?v=2")
    refute Robots.allowed?(rules, "/szukaj")
    assert Robots.allowed?(rules, "/szukaj/pokoje")
  end

  test "several wildcards in one rule are matched in order" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /*/druk/*.html$\n")

    refute Robots.allowed?(rules, "/oferta/druk/pokoje.html")
    assert Robots.allowed?(rules, "/oferta/pokoje.html")
    assert Robots.allowed?(rules, "/oferta/druk/pokoje.htm")
  end

  test "a dollar sign alone in the middle of a rule is a plain character" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /a$b\n")

    refute Robots.allowed?(rules, "/a$b/c")
    assert Robots.allowed?(rules, "/a")
  end

  test "only the group for every crawler counts" do
    robots_txt = """
    User-agent: Googlebot
    Disallow: /dla-google

    User-agent: *
    Disallow: /prywatne
    """

    %{rules: rules} = Robots.parse(robots_txt)

    assert Robots.allowed?(rules, "/dla-google")
    refute Robots.allowed?(rules, "/prywatne")
  end

  test "a group naming several crawlers, every crawler among them, counts" do
    %{rules: rules} = Robots.parse("User-agent: Googlebot\nUser-agent: *\nDisallow: /prywatne\n")

    refute Robots.allowed?(rules, "/prywatne")
  end

  test "comments, blank lines, odd case and Windows line ends are read" do
    robots_txt = "# zasady\r\nUSER-AGENT : * # wszyscy\r\n\r\ndisallow: /tmp # tymczasowe\r\nnot a rule\r\n"

    %{rules: rules} = Robots.parse(robots_txt)

    refute Robots.allowed?(rules, "/tmp/x")
  end

  test "lines the crawl doesn't use, and an empty sitemap line, are skipped" do
    robots_txt = "User-agent: *\nCrawl-delay: 10\nSitemap:\nHost: hotel-testowy.example\nDisallow: /tmp\n"

    assert %{rules: [%{"allow" => false, "pattern" => "/tmp"}], sitemaps: []} = Robots.parse(robots_txt)
  end

  test "two wildcards in a row match like one" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /a**b\n")

    refute Robots.allowed?(rules, "/a/x/b")
    assert Robots.allowed?(rules, "/a/x")
  end

  test "an empty disallow allows everything" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow:\n")

    assert rules == []
    assert Robots.allowed?(rules, "/")
  end

  test "sitemap lines are read wherever they are" do
    robots_txt = """
    Sitemap: https://hotel-testowy.example/sitemap.xml
    User-agent: Googlebot
    Disallow: /x
    sitemap: https://hotel-testowy.example/strony.xml
    """

    assert %{sitemaps: ["https://hotel-testowy.example/sitemap.xml", "https://hotel-testowy.example/strony.xml"]} =
             Robots.parse(robots_txt)
  end

  test "no rules allow everything" do
    assert %{rules: [], sitemaps: []} = Robots.parse("")
    assert Robots.allowed?([], "/admin")
  end

  test "rules read back from stored facts work the same" do
    %{rules: rules} = Robots.parse("User-agent: *\nDisallow: /admin\n")

    stored = rules |> Jason.encode!() |> Jason.decode!()

    refute Robots.allowed?(stored, "/admin")
  end

  test "a huge robots.txt keeps a bounded number of rules and sitemaps and is read quickly" do
    robots_txt =
      "User-agent: *\n" <> String.duplicate("Disallow: /*a*a*a*a*a*a*a*a*b\nSitemap: https://x.example/s.xml\n", 40_000)

    %{rules: rules, sitemaps: sitemaps} = Robots.parse(robots_txt)

    assert Enum.count(rules) == 500
    assert Enum.count(sitemaps) == 50
    assert Robots.allowed?(rules, "/" <> String.duplicate("a", 2_000))
  end

  test "a rule longer than 512 bytes or with more than ten wildcards is dropped" do
    longest = "/" <> String.duplicate("a", 511)
    too_long = "/" <> String.duplicate("b", 512)
    ten_wildcards = "/" <> String.duplicate("*c", 10)
    eleven_wildcards = "/" <> String.duplicate("*d", 11)

    %{rules: rules} =
      Robots.parse(
        "User-agent: *\n" <> Enum.map_join([longest, too_long, ten_wildcards, eleven_wildcards], &"Disallow: #{&1}\n")
      )

    assert Enum.map(rules, & &1["pattern"]) == [longest, ten_wildcards]
  end

  test "a hostile robots.txt of long many-wildcard rules keeps none of them" do
    hostile = "/" <> String.duplicate("*a", 900)
    robots_txt = "User-agent: *\n" <> String.duplicate("Disallow: #{hostile}\n", 1_000)

    assert %{rules: []} = Robots.parse(robots_txt)
  end

  test "a sitemap line that is not a web address of at most 2,048 bytes is skipped" do
    longest = "https://hotel-testowy.example/" <> String.duplicate("a", 2_048 - 30)
    too_long = longest <> "b"

    robots_txt =
      "Sitemap: #{longest}\nSitemap: #{too_long}\nSitemap: /mapa.xml\nSitemap: ftp://hotel-testowy.example/m.xml\n"

    assert %{sitemaps: [^longest]} = Robots.parse(robots_txt)
  end

  test "a rule or sitemap line with bytes that are not UTF-8 or a NUL character is kept as text a jsonb column can hold" do
    robots_txt =
      "User-agent: *\nDisallow: /k\xF3d\nDisallow: /a\u0000b\nSitemap: https://hotel-testowy.example/m\xF3.xml\n"

    assert Robots.parse(robots_txt) == %{
             rules: [%{"allow" => false, "pattern" => "/k\uFFFDd"}, %{"allow" => false, "pattern" => "/ab"}],
             sitemaps: []
           }
  end
end
