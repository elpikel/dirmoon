defmodule Dirmoon.WebPage.PageFactsTest do
  use ExUnit.Case, async: true

  alias Dirmoon.WebPage.PageFacts

  @url "https://hotel-testowy.example/pokoje/"

  test "the facts that compare one page with another are counted from the page's facts" do
    types = Enum.map(1..12, &"Typ#{&1}")

    html = """
    <html><head><title>Hotel dla psów</title>
    <script type="application/ld+json">#{Jason.encode!(%{"@graph" => Enum.map(types, &%{"@type" => &1})})}</script>
    </head><body>
    <h1>Hotel</h1><h2>Pokoje</h2><h3>Ceny</h3><h2>Kontakt</h2>
    <p>Jeden dwa trzy cztery</p><img src="/a.jpg" alt="Pies"><img src="/b.jpg">
    <a href="tel:+48500000001">Zadzwoń</a><a href="mailto:biuro@hotel-testowy.example">Napisz</a>
    <form><input name="imie"></form>
    </body></html>
    """

    comparison = html |> PageFacts.from_html(@url) |> PageFacts.comparison()

    assert comparison == %{
             "word_count" => comparison["word_count"],
             "main_heading_count" => 1,
             "sub_heading_count" => 3,
             "structured_data_types" => Enum.take(types, 10),
             "images" => 2,
             "title_length" => 14,
             "ways_to_act" => %{"phone_links" => 1, "email_links" => 1, "forms" => 1, "button_links" => 0}
           }

    assert comparison["word_count"] > 0
  end

  test "a compared fact that is missing or of an unexpected type is empty, never a guess" do
    assert PageFacts.comparison(%{}) == %{
             "word_count" => nil,
             "main_heading_count" => nil,
             "sub_heading_count" => nil,
             "structured_data_types" => [],
             "images" => nil,
             "title_length" => nil,
             "ways_to_act" => nil
           }

    odd = %{
      "word_count" => -1,
      "main_headings" => "Hotel",
      "structured_data_types" => ["LocalBusiness", 7, String.duplicate("a", 101)],
      "images" => "2",
      "title" => 12,
      "ways_to_act" => %{"phone_links" => "1", "forms" => 2}
    }

    assert %{
             "word_count" => nil,
             "main_heading_count" => nil,
             "structured_data_types" => ["LocalBusiness"],
             "images" => nil,
             "title_length" => nil,
             "ways_to_act" => %{"phone_links" => nil, "email_links" => nil, "forms" => 2, "button_links" => nil}
           } = PageFacts.comparison(odd)
  end

  test "an empty document gives every fact empty" do
    assert PageFacts.from_html("", @url) == %{
             "title" => nil,
             "description" => nil,
             "canonical" => nil,
             "robots" => nil,
             "noindex" => false,
             "main_headings" => [],
             "sub_headings" => [],
             "word_count" => 0,
             "text_fingerprint" => nil,
             "images" => 0,
             "images_without_description" => 0,
             "internal_links" => [],
             "external_links" => [],
             "language" => nil,
             "viewport" => false,
             "structured_data_types" => [],
             "business_name" => nil,
             "phones" => [],
             "emails" => [],
             "password_field" => false,
             "ways_to_act" => %{"phone_links" => 0, "email_links" => 0, "forms" => 0, "button_links" => 0}
           }
  end

  test "malformed markup and invalid bytes are read the way a browser reads them" do
    html = ~s(<html lang="pl"><h1>Pok\xFFoje <b>bez końca <a href="/a" <img src=x alt=""><form><input name=q>)

    facts = PageFacts.from_html(html, @url)

    assert facts["language"] == "pl"
    assert facts["main_headings"] == ["Pok oje bez końca"]
    assert facts["internal_links"] == ["https://hotel-testowy.example/a"]
    assert facts["images"] == 0
    assert facts["ways_to_act"]["forms"] == 1
  end

  test "binary garbage gives a facts map" do
    garbage = :binary.copy(<<0, 255, ?<, ?!, ?-, 0xC3, ?&, ?#, ?>, 7>>, 100_000)

    assert %{"main_headings" => [], "internal_links" => []} = PageFacts.from_html(garbage, @url)
  end

  test "a page too deeply nested to parse gives every fact empty" do
    html = String.duplicate("<div>", 1_000) <> ~s(<h1>Pokoje</h1><a href="/cennik">Cennik</a>)

    assert PageFacts.from_html(html, @url) == PageFacts.from_html("", @url)
  end

  test "an address the links can't be resolved against keeps only absolute links" do
    html = ~s(<a href="/pokoje">Pokoje</a><a href="https://inny.example/">Inny</a>)

    facts = PageFacts.from_html(html, "not an address")

    assert facts["internal_links"] == []
    assert facts["external_links"] == ["https://inny.example/"]
  end

  test "the title is the first title's text with character references decoded" do
    html = "<head><title>\n Pokoje &amp; ceny </title></head><svg><title>Ikona</title></svg><title>Drugi</title>"

    assert %{"title" => "Pokoje & ceny"} = PageFacts.from_html(html, @url)
  end

  test "every named character reference is decoded" do
    html = ~s(<title>Caf&eacute; &Uuml;ber</title><meta name="description" content="Caf&eacute;">)

    assert %{"title" => "Café Über", "description" => "Café"} = PageFacts.from_html(html, @url)
  end

  test "a blank title counts as no title" do
    assert %{"title" => nil} = PageFacts.from_html("<title>  </title>", @url)
  end

  test "an icon's title is not the page title" do
    assert %{"title" => nil} = PageFacts.from_html("<svg><title>Ikona</title></svg>", @url)
  end

  test "the description comes from the description meta tag, whatever the case of its name" do
    html = ~s(<meta name="Description" content="Pokoje nad jeziorem &amp; śniadanie">)

    assert %{"description" => "Pokoje nad jeziorem & śniadanie"} = PageFacts.from_html(html, @url)
  end

  test "a description meta tag without content counts as no description" do
    assert %{"description" => nil} = PageFacts.from_html(~s(<meta name="description">), @url)
  end

  test "the canonical address is resolved against the page address" do
    html = ~s(<link rel="Canonical" href="/pokoje">)

    assert %{"canonical" => "https://hotel-testowy.example/pokoje"} = PageFacts.from_html(html, @url)
  end

  test "a canonical link among other rel values is found" do
    html = ~s(<link rel="stylesheet" href="/a.css"><link rel="alternate canonical" href="https://hotel-testowy.example/">)

    assert %{"canonical" => "https://hotel-testowy.example/"} = PageFacts.from_html(html, @url)
  end

  test "the robots meta is read lower-cased and noindex is recognised" do
    html = ~s(<meta name="robots" content="NoIndex, Follow">)

    assert %{"robots" => "noindex, follow", "noindex" => true} = PageFacts.from_html(html, @url)
  end

  test "a robots meta of none means noindex" do
    assert %{"noindex" => true} = PageFacts.from_html(~s(<meta name="robots" content="none">), @url)
  end

  test "a robots meta that allows indexing is not noindex" do
    html = ~s(<meta content="index, follow" name="robots">)

    assert %{"robots" => "index, follow", "noindex" => false} = PageFacts.from_html(html, @url)
  end

  test "main headings are the texts of every non-blank h1" do
    html = "<h1>Pokoje <em>nad jeziorem</em></h1><H1 class=\"x\">Cennik</H1><h1> </h1>"

    assert %{"main_headings" => ["Pokoje nad jeziorem", "Cennik"]} = PageFacts.from_html(html, @url)
  end

  test "sub-headings are the h2 and h3 texts with their level, in page order" do
    html = "<h2>Pokoje</h2><h4>Pominięty</h4><h3>Dwuosobowy</h3><h2></h2>"

    assert %{"sub_headings" => [%{"level" => 2, "text" => "Pokoje"}, %{"level" => 3, "text" => "Dwuosobowy"}]} =
             PageFacts.from_html(html, @url)
  end

  test "main headings are capped at fifty" do
    html = String.duplicate("<h1>Pokój</h1>", 60)

    assert %{"main_headings" => main_headings} = PageFacts.from_html(html, @url)
    assert main_headings == List.duplicate("Pokój", 50)
  end

  test "sub-headings are capped at fifty" do
    html = String.duplicate("<h2>Pokój</h2>", 60)

    assert %{"sub_headings" => sub_headings} = PageFacts.from_html(html, @url)
    assert sub_headings == List.duplicate(%{"level" => 2, "text" => "Pokój"}, 50)
  end

  test "the word count counts the visible words only" do
    html =
      "<head><title>Tytuł nie liczy się</title></head><body><p>Pokoje nad jeziorem, 2 osoby &mdash; ok</p><script>var a = 1;</script></body>"

    assert %{"word_count" => 6} = PageFacts.from_html(html, @url)
  end

  test "two pages with the same visible text, differently marked up, share a text fingerprint" do
    first = PageFacts.from_html("<div><p>Pokoje  nad jeziorem</p></div>", @url)
    second = PageFacts.from_html("<section>pokoje\nNAD <b>jeziorem</b></section>", "https://hotel-testowy.example/inne")

    assert is_binary(first["text_fingerprint"])
    assert first["text_fingerprint"] == second["text_fingerprint"]
  end

  test "pages with different text have different fingerprints" do
    first = PageFacts.from_html("<p>Pokoje nad jeziorem</p>", @url)
    second = PageFacts.from_html("<p>Pokoje w górach</p>", @url)

    refute first["text_fingerprint"] == second["text_fingerprint"]
  end

  test "images are counted, and those whose alt is missing or blank have no description" do
    html = ~s(<img src="a.jpg" alt="Pokój"><IMG src="b.jpg" alt=" "><img src="c.jpg"><img alt='Taras' src="d.jpg"/>)

    assert %{"images" => 4, "images_without_description" => 2} = PageFacts.from_html(html, @url)
  end

  test "links are resolved, de-duplicated, stripped of fragments and split into internal and external" do
    html = """
    <a href="/cennik">Cennik</a>
    <a href="cennik#doba">Pokoje</a>
    <a href='https://www.hotel-testowy.example/kontakt'>Kontakt</a>
    <a href=https://HOTEL-TESTOWY.example/cennik#top>Cennik</a>
    <a href="https://mapy.example/hotel?a=1&amp;b=2">Mapa</a>
    <a href="https://mapy.example/hotel?a=1&b=2#x">Mapa</a>
    <a href="#gora">Do góry</a>
    <a href="javascript:void(0)">Menu</a>
    <a href="ftp://pliki.example/">Pliki</a>
    <a href="tel:+48 600 000 000">Zadzwoń</a>
    <a href="http://[zły adres">Zły</a>
    """

    facts = PageFacts.from_html(html, @url)

    assert facts["internal_links"] == [
             "https://hotel-testowy.example/cennik",
             "https://hotel-testowy.example/pokoje/cennik",
             "https://www.hotel-testowy.example/kontakt",
             "https://hotel-testowy.example/pokoje/"
           ]

    assert facts["external_links"] == ["https://mapy.example/hotel?a=1&b=2"]
  end

  test "a link or canonical address longer than 2,048 bytes is left out" do
    too_long = "/" <> String.duplicate("a", 2_048)
    external_too_long = "https://mapy.example/" <> String.duplicate("b", 2_048)

    html =
      ~s(<link rel="canonical" href="#{too_long}"><a href="#{too_long}">1</a><a href="#{external_too_long}">2</a><a href="/cennik">3</a>)

    assert %{"canonical" => nil, "internal_links" => ["https://hotel-testowy.example/cennik"], "external_links" => []} =
             PageFacts.from_html(html, @url)
  end

  test "an anchor without an address is not a link" do
    html = ~s(<a name="kotwica" class="btn">Bez adresu</a>)

    assert %{"internal_links" => [], "external_links" => [], "ways_to_act" => %{"button_links" => 0}} =
             PageFacts.from_html(html, @url)
  end

  test "a closing angle bracket inside an attribute value does not cut the tag" do
    html = ~s(<a title="a>b" href="/cennik" class="btn">Cennik</a>)

    assert %{"internal_links" => ["https://hotel-testowy.example/cennik"], "ways_to_act" => %{"button_links" => 1}} =
             PageFacts.from_html(html, @url)
  end

  test "custom elements whose names start like a known tag are not that tag" do
    html = ~s(<html-x lang="en"></html-x><a-b href="/cennik" class="btn">Cennik</a-b>)

    assert %{"language" => nil, "internal_links" => [], "ways_to_act" => %{"button_links" => 0}} =
             PageFacts.from_html(html, @url)
  end

  test "a page on the www host counts links on the bare host as internal" do
    html = ~s(<a href="https://hotel-testowy.example/">Start</a><a href="https://sklep.hotel-testowy.example/">Sklep</a>)

    facts = PageFacts.from_html(html, "https://www.hotel-testowy.example/")

    assert facts["internal_links"] == ["https://hotel-testowy.example/"]
    assert facts["external_links"] == ["https://sklep.hotel-testowy.example/"]
  end

  test "links are resolved against the page's base address when it declares one" do
    html = ~s(<base href="/en/"><a href="rooms">Rooms</a>)

    assert %{"internal_links" => ["https://hotel-testowy.example/en/rooms"]} = PageFacts.from_html(html, @url)
  end

  test "a base address that is not a web address is ignored" do
    html = ~s(<base href="mailto:recepcja@hotel-testowy.example"><a href="cennik">Cennik</a>)

    assert %{"internal_links" => ["https://hotel-testowy.example/pokoje/cennik"]} = PageFacts.from_html(html, @url)
  end

  test "links inside scripts and comments are not links" do
    html = ~s(<!-- <a href="/stary">Stary</a> --><script>var a = '<a href="/js">x</a>';</script><a href="/nowy">Nowy</a>)

    assert %{"internal_links" => ["https://hotel-testowy.example/nowy"]} = PageFacts.from_html(html, @url)
  end

  test "the declared language comes from the html element" do
    assert %{"language" => "pl-PL"} =
             PageFacts.from_html(~s(<!doctype html><HTML LANG=" pl-PL "><body></body></HTML>), @url)
  end

  test "a blank language counts as none declared" do
    assert %{"language" => nil} = PageFacts.from_html(~s(<html lang="">), @url)
  end

  test "a viewport meta tag is noticed" do
    html = ~s(<meta name="viewport" content="width=device-width, initial-scale=1">)

    assert %{"viewport" => true} = PageFacts.from_html(html, @url)
  end

  test "structured data types are collected from every JSON-LD script, including a graph and nested items" do
    html = """
    <script type="application/ld+json">
      {"@context": "https://schema.org", "@type": "Hotel", "name": "Hotel Testowy",
       "address": {"@type": "PostalAddress"}, "amenityFeature": [{"@type": "LocationFeatureSpecification"}]}
    </script>
    <script type='application/ld+json'>
      {"@graph": [{"@type": ["WebPage", "FAQPage"]}, {"@type": "Hotel"}, {"@type": 7}]}
    </script>
    <script type="application/ld+json">[{"@type": "BreadcrumbList"}]</script>
    <script type="text/javascript">{"@type": "NotStructuredData"}</script>
    """

    assert %{
             "structured_data_types" => [
               "Hotel",
               "PostalAddress",
               "LocationFeatureSpecification",
               "WebPage",
               "FAQPage",
               "BreadcrumbList"
             ]
           } =
             PageFacts.from_html(html, @url)
  end

  test "invalid JSON-LD is skipped and the valid scripts still count" do
    html = """
    <script type="application/ld+json">{"@type": "Hotel",</script>
    <script type="application/ld+json">"just a string"</script>
    <script type="application/ld+json">{"@type": "Restaurant"}</script>
    """

    assert %{"structured_data_types" => ["Restaurant"]} = PageFacts.from_html(html, @url)
  end

  test "the business name comes from the structured data of a business" do
    html = """
    <script type="application/ld+json">
      {"@graph": [{"@type": "WebSite", "name": "Strona"}, {"@type": "LocalBusiness", "name": " Hotel Testowy "}]}
    </script>
    """

    assert %{"business_name" => "Hotel Testowy"} = PageFacts.from_html(html, @url)
  end

  test "a business type among several types gives the business name" do
    html = ~s(<script type="application/ld+json">{"@type": ["Place", "Organization"], "name": "Hotel Testowy"}</script>)

    assert %{"business_name" => "Hotel Testowy"} = PageFacts.from_html(html, @url)
  end

  test "structured data without a business or without its name gives no business name" do
    html = """
    <script type="application/ld+json">{"@type": "WebSite", "name": "Strona"}</script>
    <script type="application/ld+json">{"@type": "Organization", "name": "  "}</script>
    <script type="application/ld+json">{"@type": "LocalBusiness"}</script>
    """

    assert %{"business_name" => nil} = PageFacts.from_html(html, @url)
  end

  test "phones come from tel links, normalised to digits with a leading plus" do
    html = """
    <a href="tel:+48 600-000-000">Zadzwoń</a>
    <a href="TEL:%2B48%20600%20000%20000">Zadzwoń</a>
    <a href="tel:(22) 123 45 67">Biuro</a>
    <a href="tel:">Pusty</a>
    <a href="tel:%ZZ600%E2">Zepsuty</a>
    """

    facts = PageFacts.from_html(html, @url)

    assert facts["phones"] == ["+48600000000", "221234567", "600"]
    assert facts["ways_to_act"]["phone_links"] == 5
  end

  test "a phone's parameters, such as an extension, are not part of its number" do
    html = ~s(<a href="tel:+48600000000;ext=12">Zadzwoń</a><a href="tel:+48 22 123 45 67;phone-context=example">Biuro</a>)

    assert %{"phones" => ["+48600000000", "+48221234567"]} = PageFacts.from_html(html, @url)
  end

  test "e-mails come from mailto links, lower-cased, without their parameters" do
    html = """
    <a href="mailto:Recepcja@Hotel-Testowy.example?subject=Rezerwacja">Napisz</a>
    <a href="mailto:recepcja@hotel-testowy.example,biuro@hotel-testowy.example">Napisz</a>
    <a href="mailto:">Pusty</a>
    """

    facts = PageFacts.from_html(html, @url)

    assert facts["emails"] == ["recepcja@hotel-testowy.example", "biuro@hotel-testowy.example"]
    assert facts["ways_to_act"]["email_links"] == 3
  end

  test "only forms with a field a visitor can fill in are counted" do
    html = """
    <form><input type="text" name="imie"><button>Wyślij</button></form>
    <form><textarea name="wiadomosc"></textarea></form>
    <form><select name="pokoj"><option>1</option></select></form>
    <form><input type="hidden" name="token"><input type='HIDDEN' name="a"></form>
    <form></form>
    """

    assert %{"ways_to_act" => %{"forms" => 3}} = PageFacts.from_html(html, @url)
  end

  test "a password field is noticed" do
    html = ~s(<form><input name="login"><input type="password" name="haslo"></form>)

    assert %{"password_field" => true} = PageFacts.from_html(html, @url)
  end

  test "links styled as buttons are counted as ways to act" do
    html = """
    <a href="/rezerwacja" class="btn btn-primary">Rezerwuj</a>
    <a href="/kontakt" class="wp-block-button__link">Kontakt</a>
    <a href="/oferta" role="button">Oferta</a>
    <a href="/o-nas" class="menu-link">O nas</a>
    """

    assert %{"ways_to_act" => %{"button_links" => 3}} = PageFacts.from_html(html, @url)
  end

  test "bytes that are not UTF-8 and NUL characters never reach a fact, whether in the page or its structured data" do
    html =
      ~s(<html lang="p\xF3l"><title>Pok\xF3j</title><h1>Pok\u0000ój</h1>) <>
        ~s(<script type="application/ld+json">{"@type": ["Hotel\\u0000", "Place"], "name": "A\\u0000B"}</script>) <>
        ~s(<a href="mailto:recepcja%00@hotel-testowy.example">E-mail</a><a href="tel:+48%00600">Tel</a>)

    facts = PageFacts.from_html(html, @url)

    assert %{
             "language" => "p�l",
             "title" => "Pok j",
             "main_headings" => ["Pokój"],
             "structured_data_types" => ["Hotel", "Place"],
             "business_name" => "AB",
             "emails" => ["recepcja@hotel-testowy.example"],
             "phones" => ["+48600"]
           } = facts

    assert facts |> strings() |> Enum.all?(&(String.valid?(&1) and not String.contains?(&1, <<0>>)))
  end

  test "the title and description are cut to 1,000 bytes and the robots directives to 200, at a character boundary" do
    long = String.duplicate("ó", 1_500)

    html =
      ~s(<title>#{long}</title><meta name="description" content="#{long}">) <>
        ~s(<meta name="robots" content="#{String.duplicate("noindex, ", 100)}">)

    facts = PageFacts.from_html(html, @url)

    assert facts["title"] == String.duplicate("ó", 500)
    assert facts["description"] == String.duplicate("ó", 500)
    assert byte_size(facts["robots"]) <= 200
    assert facts["noindex"]
  end

  test "a heading is cut to 300 bytes" do
    html = "<h1>#{String.duplicate("ó", 400)}</h1><h2>#{String.duplicate("a", 400)}</h2>"

    assert %{"main_headings" => [main], "sub_headings" => [%{"text" => sub}]} = PageFacts.from_html(html, @url)
    assert main == String.duplicate("ó", 150)
    assert sub == String.duplicate("a", 300)
  end

  test "a declared language longer than 35 bytes is left out" do
    assert %{"language" => "pl-PL"} = PageFacts.from_html(~s(<html lang="pl-PL">), @url)
    assert %{"language" => nil} = PageFacts.from_html(~s(<html lang="#{String.duplicate("a", 36)}">), @url)
  end

  test "the business name is cut to 300 bytes" do
    html = ~s(<script type="application/ld+json">{"@type": "Hotel", "name": "#{String.duplicate("ó", 200)}"}</script>)

    assert %{"business_name" => business_name} = PageFacts.from_html(html, @url)
    assert business_name == String.duplicate("ó", 150)
  end

  test "structured data keeps at most fifty types, and a type longer than 100 bytes is left out" do
    types = Enum.map(1..60, &"Typ#{&1}")
    too_long = String.duplicate("T", 101)
    html = ~s(<script type="application/ld+json">{"@type": #{Jason.encode!([too_long | types])}}</script>)

    assert %{"structured_data_types" => kept} = PageFacts.from_html(html, @url)
    assert kept == Enum.take(types, 50)
  end

  test "at most fifty phones and fifty e-mails are kept, and one longer than 320 bytes is left out" do
    phones = Enum.map_join(1..60, &~s(<a href="tel:+48600000#{100 + &1}">T</a>))
    emails = Enum.map_join(1..60, &~s(<a href="mailto:biuro#{&1}@hotel-testowy.example">E</a>))

    too_long =
      ~s(<a href="tel:+#{String.duplicate("1", 320)}">T</a><a href="mailto:#{String.duplicate("a", 320)}@x.example">E</a>)

    assert %{"phones" => kept_phones, "emails" => kept_emails} = PageFacts.from_html(too_long <> phones <> emails, @url)
    assert kept_phones == Enum.map(1..50, &"+48600000#{100 + &1}")
    assert kept_emails == Enum.map(1..50, &"biuro#{&1}@hotel-testowy.example")
  end

  test "at most a hundred internal and fifty external links are kept" do
    internal = Enum.map_join(1..120, &~s(<a href="/strona-#{&1}">S</a>))
    external = Enum.map_join(1..60, &~s(<a href="https://inny-#{&1}.example/">I</a>))

    assert %{"internal_links" => internal_links, "external_links" => external_links} =
             PageFacts.from_html(internal <> external, @url)

    assert internal_links == Enum.map(1..100, &"https://hotel-testowy.example/strona-#{&1}")
    assert external_links == Enum.map(1..50, &"https://inny-#{&1}.example/")
  end

  test "long links are kept only while the internal ones fit in 64 KiB and the external ones in 16 KiB" do
    long_path = String.duplicate("a", 1_990)
    internal = Enum.map_join(1..100, &~s(<a href="/#{&1}-#{long_path}">S</a>))
    external = Enum.map_join(1..50, &~s(<a href="https://inny.example/#{&1}-#{long_path}">I</a>))

    assert %{"internal_links" => internal_links, "external_links" => external_links} =
             PageFacts.from_html(internal <> external, @url)

    assert internal_links |> Enum.map(&byte_size/1) |> Enum.sum() <= 65_536
    assert external_links |> Enum.map(&byte_size/1) |> Enum.sum() <= 16_384
    assert Enum.count(internal_links) == div(65_536, byte_size(hd(internal_links)))
    assert Enum.count(external_links) == div(16_384, byte_size(hd(external_links)))
  end

  test "a page that reaches every cap gives facts of at most 160 KB as JSON" do
    long_text = String.duplicate("ó", 2_000)
    long_path = String.duplicate("a", 2_000)

    html =
      ~s(<html lang="#{String.duplicate("a", 35)}"><title>#{long_text}</title>) <>
        ~s(<meta name="description" content="#{long_text}"><meta name="robots" content="#{long_text}">) <>
        ~s(<link rel="canonical" href="/#{long_path}">) <>
        String.duplicate("<h1>#{long_text}</h1><h2>#{long_text}</h2>", 60) <>
        ~s(<script type="application/ld+json">{"@type": #{Jason.encode!(["Hotel" | Enum.map(1..60, &"#{&1}#{String.duplicate("T", 96)}")])}, ) <>
        ~s("name": "#{long_text}"}</script>) <>
        Enum.map_join(1..60, &~s(<a href="tel:+#{&1}#{String.duplicate("1", 316)}">T</a>)) <>
        Enum.map_join(1..60, &~s(<a href="mailto:#{&1}#{String.duplicate("a", 300)}@x.example">E</a>)) <>
        Enum.map_join(1..120, &~s(<a href="/#{&1}#{long_path}">S</a>)) <>
        Enum.map_join(1..60, &~s(<a href="https://inny.example/#{&1}#{long_path}">I</a>))

    facts = PageFacts.from_html(html, @url)

    assert Enum.count(facts["main_headings"]) == 50
    assert Enum.count(facts["structured_data_types"]) == 50
    assert Enum.count(facts["phones"]) == 50
    assert Enum.count(facts["emails"]) == 50
    assert byte_size(facts["business_name"]) == 300
    assert facts["internal_links"] |> Enum.map(&byte_size/1) |> Enum.sum() > 60_000
    assert facts["external_links"] |> Enum.map(&byte_size/1) |> Enum.sum() > 14_000
    assert byte_size(Jason.encode!(facts)) <= 160_000
  end

  defp strings(value) when is_binary(value), do: [value]
  defp strings(value) when is_map(value), do: value |> Map.values() |> Enum.flat_map(&strings/1)
  defp strings(value) when is_list(value), do: Enum.flat_map(value, &strings/1)
  defp strings(_value), do: []

  test "a link written with the page's international host in its Unicode form is internal, in its ASCII form" do
    html = """
    <a href="https://www.Żółw.pl/oferta">Oferta</a>
    <a href="https://xn--w-uga1v8h.pl/kontakt">Kontakt</a>
    <a href="https://münchen.de/hotel">Hotel</a>
    <a href="https://-żółw.pl/zły">Zły</a>
    <link rel="canonical" href="https://żółw.pl/">
    """

    facts = PageFacts.from_html(html, "https://xn--w-uga1v8h.pl/")

    assert facts["internal_links"] == ["https://www.xn--w-uga1v8h.pl/oferta", "https://xn--w-uga1v8h.pl/kontakt"]
    assert facts["external_links"] == ["https://xn--mnchen-3ya.de/hotel"]
    assert facts["canonical"] == "https://xn--w-uga1v8h.pl/"
  end
end
