defmodule Dirmoon.Pages.TemplateTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Template

  test "the page has the five blocks in the fixed order" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query("[data-block]") |> LazyHTML.attribute("data-block") ==
             ["header", "hero", "jump-strip", "section", "section", "section", "section", "closing"]
  end

  test "the hero holds the breadcrumb, H1, intro, call to action, phone and three Fact Tiles in order" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query(".hero-inner > *") |> LazyHTML.attribute("class") ==
             ["breadcrumb", "hero-title", "intro", "hero-actions", "fact-tiles"]

    assert document |> LazyHTML.query(".hero-actions > *") |> LazyHTML.attribute("class") ==
             ["button button-dark", "phone"]

    assert document |> LazyHTML.query(".fact-tiles .fact-tile") |> Enum.count() == 3
    assert document |> LazyHTML.query(".hero h1") |> text() == "Nagłówek testowy strony"
  end

  test "only the first section has the short answer box and a lime badge" do
    document = render_document(brief_params())

    assert document
           |> LazyHTML.query("[data-block=section]")
           |> Enum.map(&(&1 |> LazyHTML.query(".short-answer") |> Enum.count())) == [1, 0, 0, 0]

    assert document |> LazyHTML.query(".badge") |> LazyHTML.attribute("class") |> Enum.map(&String.split/1) ==
             [["badge", "badge-first"], ["badge"], ["badge"], ["badge"]]

    assert document |> LazyHTML.query(".badge") |> Enum.map(&text/1) == ["01", "02", "03", "04"]
  end

  test "the header has the business name, up to three nav links to the first sections and a call to action" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query("header .business-name") |> text() == "Firma Testowa Alfa"

    assert document |> LazyHTML.query("header nav a") |> LazyHTML.attribute("href") ==
             ["#sekcja-1", "#sekcja-2", "#kontakt"]

    assert document |> LazyHTML.query("header nav a") |> Enum.map(&text/1) ==
             ["Pierwsza", "Druga", "Przycisk testowy"]
  end

  test "the closing band is the contact anchor with the prompt, contact details and a lime button" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query("footer#kontakt .closing-prompt") |> text() == "Zamknięcie testowe?"

    assert document |> LazyHTML.query("footer#kontakt .contact a[href^='mailto:']") |> text() ==
             "kontakt@strona-testowa.example"

    assert document |> LazyHTML.query("footer#kontakt .contact .address") |> text() ==
             "ul. Testowa 1, 00-001 Testowo"

    assert document |> LazyHTML.query("footer#kontakt a.button-lime") |> Enum.count() == 1
  end

  test "the document is a Polish HTML page with charset, viewport, title and description" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == ["pl"]
    assert document |> LazyHTML.query("meta[charset]") |> Enum.count() == 1
    assert document |> LazyHTML.query("meta[name=viewport]") |> Enum.count() == 1
    assert document |> LazyHTML.query("title") |> text() == "Tytuł testowy strony"

    assert document |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content") ==
             ["Wstęp testowy strony."]
  end

  test "the rendered document starts with the doctype" do
    assert brief_params()
           |> build_brief()
           |> Template.render(%{mode: :new_idea})
           |> String.starts_with?("<!DOCTYPE html>")
  end

  test "the page carries its styles inline and loads no stylesheet, font or script" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query("style") |> Enum.count() == 1
    assert document |> LazyHTML.query("link") |> Enum.count() == 0
    assert document |> LazyHTML.query("script") |> Enum.count() == 0
    assert document |> LazyHTML.query("[src]") |> Enum.count() == 0
    refute Template.css() =~ "@import"
    refute Template.css() =~ ~r/url\(\s*['"]?(https?:)?\/\//
  end

  test "with a plausible domain the Plausible snippet is the only script" do
    document = render_document(Map.put(brief_params(), "plausible_domain", "strona-testowa.example"))

    assert [script] = document |> LazyHTML.query("head script") |> Enum.to_list()
    assert LazyHTML.attribute(script, "src") == ["https://plausible.io/js/script.js"]
    assert LazyHTML.attribute(script, "data-domain") == ["strona-testowa.example"]
    assert LazyHTML.attribute(script, "defer") == [""]
    assert document |> LazyHTML.query("script") |> Enum.count() == 1
  end

  test "every colour in the stylesheet is a design token value" do
    tokens = "docs/design/tokens.css" |> File.read!() |> String.upcase()

    colours = ~r/#[0-9a-fA-F]{3,8}\b/ |> Regex.scan(Template.css()) |> List.flatten()

    assert colours != []
    assert Enum.reject(colours, &String.contains?(tokens, String.upcase(&1))) == []
    refute Template.css() =~ ~r/rgba?\(|hsla?\(/
  end

  test "missing phone, price, e-mail and address show their Placeholders" do
    params =
      brief_params()
      |> Map.drop(["phone", "email", "address"])
      |> Map.put("fact_tiles", [
        %{"label" => "Cena testowa", "value" => ""},
        %{"label" => "Etykieta B", "value" => "Wartość B"},
        %{"label" => "Etykieta C", "value" => "Wartość C"}
      ])

    placeholders = params |> render_document() |> LazyHTML.query(".placeholder") |> Enum.map(&text/1)

    assert "[TELEFON]" in placeholders
    assert "[CENA]" in placeholders
    assert "[E-MAIL]" in placeholders
    assert "[ADRES]" in placeholders
  end

  test "a missing phone is plain placeholder text, not a link" do
    document = brief_params() |> Map.delete("phone") |> render_document()

    assert document |> LazyHTML.query("a[href^='tel:']") |> Enum.count() == 0
    assert document |> LazyHTML.query(".hero-actions .phone .placeholder") |> text() == "[TELEFON]"
  end

  test "a missing e-mail is not a mailto link" do
    document = brief_params() |> Map.delete("email") |> render_document()

    assert document |> LazyHTML.query("a[href^='mailto:']") |> Enum.count() == 0
  end

  test "a real phone renders a tel link and no phone Placeholder" do
    document = render_document(brief_params())

    assert document |> LazyHTML.query(".hero-actions a.phone") |> LazyHTML.attribute("href") == ["tel:+48500000001"]
    refute "[TELEFON]" in (document |> LazyHTML.query(".placeholder") |> Enum.map(&text/1))
  end

  test "missing business name, intro, answers and short answer show their Placeholders" do
    params =
      brief_params()
      |> Map.drop(["business_name", "intro", "short_answer"])
      |> Map.put("sections", [%{"question" => "Pytanie testowe bez odpowiedzi?"}])

    document = render_document(params)

    assert document |> LazyHTML.query("header .business-name .placeholder") |> text() == "[NAZWA FIRMY]"
    assert document |> LazyHTML.query(".intro .placeholder") |> text() == "[WSTĘP]"
    assert document |> LazyHTML.query(".answer .placeholder") |> text() == "[ODPOWIEDŹ]"
    assert document |> LazyHTML.query(".short-answer .placeholder") |> text() == "[W SKRÓCIE]"
  end

  test "a Placeholder inside written text is shown as a Placeholder" do
    params =
      Map.put(brief_params(), "sections", [%{"question" => "Pytanie testowe?", "answer" => "Koszt to [CENA] za dzień."}])

    document = render_document(params)

    assert document |> LazyHTML.query(".answer .placeholder") |> text() == "[CENA]"
    assert document |> LazyHTML.query(".answer") |> text() =~ "Koszt to [CENA] za dzień."
  end

  test "an answer's lines become paragraphs" do
    params =
      Map.put(brief_params(), "sections", [
        %{"question" => "Pytanie testowe?", "answer" => "Pierwszy akapit testowy.\n\nDrugi akapit testowy."}
      ])

    assert params |> render_document() |> LazyHTML.query(".answer p") |> Enum.map(&text/1) ==
             ["Pierwszy akapit testowy.", "Drugi akapit testowy."]
  end

  test "HTML in Brief fields is escaped" do
    attack = "<script>alert(1)</script>"

    params =
      brief_params()
      |> Map.put("business_name", attack)
      |> Map.put("sections", [%{"question" => "Pytanie #{attack}?", "answer" => "Odpowiedź #{attack}"}])
      |> Map.put("fact_tiles", [
        %{"label" => "Etykieta A", "value" => attack},
        %{"label" => "Etykieta B", "value" => "Wartość B"},
        %{"label" => "Etykieta C", "value" => "Wartość C"}
      ])

    html = params |> build_brief() |> Template.render(%{mode: :new_idea})
    document = LazyHTML.from_document(html)

    assert document |> LazyHTML.query("script") |> Enum.count() == 0
    assert document |> LazyHTML.query("header .business-name") |> text() == attack
    assert document |> LazyHTML.query("h2#sekcja-1") |> text() == "Pytanie #{attack}?"
    assert document |> LazyHTML.query(".answer") |> text() =~ "Odpowiedź #{attack}"
    assert document |> LazyHTML.query(".fact-tile-value") |> Enum.map(&text/1) |> hd() == attack
  end

  test "a plausible domain that is not a bare host is never rendered" do
    for domain <- ["javascript:alert(1)", ~s{strona-testowa.example" onload="alert(1)}] do
      brief = %{build_brief(brief_params()) | plausible_domain: domain}

      document = brief |> Template.render(%{mode: :new_idea}) |> LazyHTML.from_document()

      assert document |> LazyHTML.query("script") |> Enum.count() == 0
      assert document |> LazyHTML.query("[onload]") |> Enum.count() == 0
    end
  end

  test "hostile text in any Brief field never becomes a tag, an event handler or a second style" do
    for hostile <- [
          "<script>alert(1)</script>",
          ~s{"><img src=x onerror=alert(1)>},
          ~s{</style></title><script>alert(1)</script>},
          ~s{' onmouseover='alert(1)},
          ~s{[CENA]<img src=x onerror=alert(1)>}
        ] do
      brief = %Brief{
        business_name: hostile,
        title: hostile,
        h1: hostile,
        slug: hostile,
        breadcrumb: hostile,
        intro: hostile,
        cta_label: hostile,
        closing_prompt: hostile,
        nav_links: [hostile, hostile, hostile],
        phone: hostile,
        email: hostile,
        address: hostile,
        short_answer: hostile,
        phrases: [hostile],
        primary_phrase: hostile,
        plausible_domain: hostile,
        fact_tiles: [%Brief.FactTile{label: hostile, value: hostile}],
        sections: [%Brief.Section{question: hostile, answer: hostile <> "\n" <> hostile}]
      }

      document = brief |> Template.render(%{mode: :new_idea}) |> LazyHTML.from_document()

      assert document |> LazyHTML.query("script") |> Enum.count() == 0, "script from #{inspect(hostile)}"
      assert document |> LazyHTML.query("img") |> Enum.count() == 0, "img from #{inspect(hostile)}"
      assert document |> LazyHTML.query("style") |> Enum.count() == 1, "style from #{inspect(hostile)}"
      assert event_handler_attributes(document) == [], "handler from #{inspect(hostile)}"
      assert document |> LazyHTML.query("a") |> LazyHTML.attribute("href") |> Enum.all?(&String.starts_with?(&1, "#"))
    end
  end

  test "a Placeholder in any written text is shown as a Placeholder" do
    params =
      brief_params()
      |> Map.put("business_name", "Firma [CENA]")
      |> Map.put("breadcrumb", "Start / [CENA]")
      |> Map.put("cta_label", "Zamów za [CENA]")
      |> Map.put("closing_prompt", "Zapytaj o [CENA]")
      |> Map.put("nav_links", ["Cennik [CENA]"])
      |> Map.put("fact_tiles", [
        %{"label" => "Cena [CENA]", "value" => "Wartość A"},
        %{"label" => "Etykieta B", "value" => "Wartość B"},
        %{"label" => "Etykieta C", "value" => "Wartość C"}
      ])
      |> Map.put("sections", [%{"question" => "Ile kosztuje [CENA]?", "answer" => "Odpowiedź testowa."}])

    document = render_document(params)

    for selector <- [
          "header .business-name .placeholder",
          ".breadcrumb .placeholder",
          "header a.button-dark .placeholder",
          ".hero-actions a.button-dark .placeholder",
          ".closing-prompt .placeholder",
          "a.button-lime .placeholder",
          "header a.nav-link .placeholder",
          ".fact-tile-label .placeholder",
          "h2#sekcja-1 .placeholder",
          "[data-block=jump-strip] a.pill .placeholder"
        ] do
      assert document |> LazyHTML.query(selector) |> Enum.map(&text/1) == ["[CENA]"], "no Placeholder in #{selector}"
    end
  end

  test "a phone with fewer than nine digits is shown as written, not as a link" do
    document = brief_params() |> Map.put("phone", "------") |> render_document()

    assert document |> LazyHTML.query("a[href^='tel:']") |> Enum.count() == 0
    assert document |> LazyHTML.query(".hero-actions .phone") |> text() == "------"
  end

  test "clearing the Plausible domain on an existing Brief removes the Plausible script" do
    brief = brief_params() |> Map.put("plausible_domain", "strona-testowa.example") |> build_brief()

    document =
      brief
      |> Brief.changeset(%{"plausible_domain" => ""})
      |> Ecto.Changeset.apply_action!(:update)
      |> Template.render(%{mode: :new_idea})
      |> LazyHTML.from_document()

    assert document |> LazyHTML.query("script") |> Enum.count() == 0
  end

  test "four sections give four jump pills linking to the section anchors" do
    document = render_document(brief_params())

    pills = LazyHTML.query(document, "[data-block=jump-strip] a")

    assert LazyHTML.attribute(pills, "href") == ["#sekcja-1", "#sekcja-2", "#sekcja-3", "#sekcja-4"]

    assert document |> LazyHTML.query("h2") |> LazyHTML.attribute("id") == [
             "sekcja-1",
             "sekcja-2",
             "sekcja-3",
             "sekcja-4"
           ]
  end

  test "a jump pill shows the question shortened to its first words without the question mark" do
    params =
      Map.put(brief_params(), "sections", [
        %{"question" => "Jak długo trwa testowa usługa alfa beta?"},
        %{"question" => "Ile to trwa?"}
      ])

    assert params |> render_document() |> LazyHTML.query("[data-block=jump-strip] a") |> Enum.map(&text/1) ==
             ["Jak długo trwa testowa", "Ile to trwa"]
  end

  test "a jump pill counts a Placeholder as one word and shows it as a Placeholder" do
    params =
      Map.put(brief_params(), "sections", [%{"question" => "Jak działa usługa [NAZWA FIRMY] w praktyce?"}])

    pill = params |> render_document() |> LazyHTML.query("[data-block=jump-strip] a")

    assert text(pill) == "Jak działa usługa [NAZWA FIRMY]"
    assert pill |> LazyHTML.query(".placeholder") |> Enum.map(&text/1) == ["[NAZWA FIRMY]"]
  end

  test "an existing site gets the same working page" do
    brief = build_brief(brief_params())

    assert Template.render(brief, %{mode: :existing_site}) == Template.render(brief, %{mode: :new_idea})
  end

  test "a section still without a question, as while editing, shows a Placeholder in its pill and heading" do
    brief = %Brief{h1: "Nagłówek w edycji", sections: [%Brief.Section{question: nil}]}

    document =
      brief
      |> Template.render(%{mode: :new_idea})
      |> LazyHTML.from_document()

    assert document |> LazyHTML.query("a.pill .placeholder") |> Enum.count() == 1
    assert document |> LazyHTML.query("h2#sekcja-1 .placeholder") |> Enum.count() == 1
  end

  test "without nav links the header nav holds only the call to action" do
    document = brief_params() |> Map.put("nav_links", []) |> render_document()

    assert document |> LazyHTML.query("header nav a") |> LazyHTML.attribute("href") == ["#kontakt"]
    assert document |> LazyHTML.query("header nav a.nav-link") |> Enum.count() == 0
  end

  test "a nav link past the last section leads to the contact anchor" do
    document =
      brief_params()
      |> Map.put("nav_links", ["Pierwsza", "Druga", "Trzecia"])
      |> Map.put("sections", [%{"question" => "Jedyne pytanie testowe?", "answer" => "Jedyna odpowiedź."}])
      |> render_document()

    assert document |> LazyHTML.query("header nav a.nav-link") |> LazyHTML.attribute("href") ==
             ["#sekcja-1", "#kontakt", "#kontakt"]
  end

  test "without Fact Tiles the hero still shows three Fact Tiles, each a Placeholder" do
    document = brief_params() |> Map.put("fact_tiles", []) |> render_document()

    fact_tiles = LazyHTML.query(document, ".fact-tiles .fact-tile")

    assert Enum.count(fact_tiles) == 3

    assert Enum.map(fact_tiles, &(&1 |> LazyHTML.query(".placeholder") |> Enum.count())) == [2, 2, 2]
  end

  test "one section gives one section block, one jump pill and the short answer box" do
    document =
      brief_params()
      |> Map.put("sections", [%{"question" => "Jedyne pytanie testowe?", "answer" => "Jedyna odpowiedź."}])
      |> render_document()

    assert document |> LazyHTML.query("[data-block=section]") |> Enum.count() == 1
    assert document |> LazyHTML.query("[data-block=jump-strip] a") |> Enum.count() == 1
    assert document |> LazyHTML.query(".short-answer") |> Enum.count() == 1
  end

  test "an e-mail typed in the editor that is not yet an address is shown as written, without a mailto link" do
    document =
      brief_params()
      |> build_brief()
      |> Map.put(:email, "napisz przez formularz")
      |> Template.render(%{mode: :new_idea})
      |> LazyHTML.from_document()

    assert document |> LazyHTML.query("a[href^='mailto:']") |> Enum.count() == 0
    assert document |> LazyHTML.query("footer#kontakt .contact") |> text() =~ "napisz przez formularz"
    refute "[E-MAIL]" in (document |> LazyHTML.query(".placeholder") |> Enum.map(&text/1))
  end

  defp text(node) do
    node
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp event_handler_attributes(document) do
    document
    |> LazyHTML.query("*")
    |> Enum.flat_map(&LazyHTML.attributes/1)
    |> List.flatten()
    |> Enum.filter(fn {name, _value} -> String.starts_with?(name, "on") end)
  end

  defp render_document(params) do
    params
    |> build_brief()
    |> Template.render(%{mode: :new_idea})
    |> LazyHTML.from_document()
  end

  defp build_brief(params) do
    %Brief{}
    |> Brief.changeset(params)
    |> Ecto.Changeset.apply_action!(:insert)
  end

  defp brief_params do
    %{
      "business_name" => "Firma Testowa Alfa",
      "title" => "Tytuł testowy strony",
      "h1" => "Nagłówek testowy strony",
      "slug" => "strona-testowa-alfa",
      "breadcrumb" => "Start / Strona testowa",
      "intro" => "Wstęp testowy strony.",
      "cta_label" => "Przycisk testowy",
      "closing_prompt" => "Zamknięcie testowe?",
      "nav_links" => ["Pierwsza", "Druga"],
      "phone" => "+48 500 000 001",
      "email" => "kontakt@strona-testowa.example",
      "address" => "ul. Testowa 1, 00-001 Testowo",
      "fact_tiles" => [
        %{"label" => "Etykieta A", "value" => "Wartość A"},
        %{"label" => "Etykieta B", "value" => "Wartość B"},
        %{"label" => "Etykieta C", "value" => "Wartość C"}
      ],
      "sections" => [
        %{"question" => "Pytanie testowe pierwsze?", "answer" => "Odpowiedź testowa pierwsza."},
        %{"question" => "Pytanie testowe drugie?", "answer" => "Odpowiedź testowa druga."},
        %{"question" => "Pytanie testowe trzecie?", "answer" => "Odpowiedź testowa trzecia."},
        %{"question" => "Pytanie testowe czwarte?", "answer" => "Odpowiedź testowa czwarta."}
      ],
      "short_answer" => "Krótka odpowiedź testowa.",
      "phrases" => ["fraza testowa"],
      "primary_phrase" => "fraza testowa"
    }
  end
end
