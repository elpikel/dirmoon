defmodule Dirmoon.Pages.PlaceholdersTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Placeholders

  test "an invented phone number becomes the phone Placeholder" do
    for phone <- ["+48 600 100 200", "600-100-200", "600100200", "58 123 45 67", "(58) 123 45 67"] do
      assert Placeholders.scrub("Zadzwoń: #{phone} w dni robocze.", []) == "Zadzwoń: [TELEFON] w dni robocze.",
             "expected #{inspect(phone)} to be replaced"
    end
  end

  test "an invented price becomes the price Placeholder" do
    assert Placeholders.scrub("Testowa usługa od 80 zł za dzień.", []) == "Testowa usługa od [CENA] za dzień."
    assert Placeholders.scrub("Pakiet testowy: 1 200,50 PLN brutto.", []) == "Pakiet testowy: [CENA] brutto."
    assert Placeholders.scrub("Wersja testowa za €15.", []) == "Wersja testowa za [CENA]."
    assert Placeholders.scrub("Opłata 25 EUR lub $30 lub 30 USD.", []) == "Opłata [CENA] lub [CENA] lub [CENA]."
    assert Placeholders.scrub("Zakres 80–120 zł.", []) == "Zakres [CENA]."
  end

  test "an invented e-mail address becomes the e-mail Placeholder" do
    assert Placeholders.scrub("Pisz na biuro@firma.example dziś.", []) == "Pisz na [E-MAIL] dziś."
  end

  test "an invented street address becomes the address Placeholder" do
    assert Placeholders.scrub("Biuro: ul. Długa 5/7, 80-001 Gdańsk.", []) == "Biuro: [ADRES]."
    assert Placeholders.scrub("Odbiór przy al. Testowa Aleja 12.", []) == "Odbiór przy [ADRES]."
    assert Placeholders.scrub("Siedziba: os. Próbne 4a.", []) == "Siedziba: [ADRES]."
    assert Placeholders.scrub("Dojazd do 80-001 Gdańsk jest prosty.", []) == "Dojazd do [ADRES] jest prosty."
  end

  test "values the User entered are kept" do
    allowed = ["+48 500 000 001", "kontakt@strona-testowa.example", "ul. Testowa 1, 00-001 Testowo", "od 99 zł"]

    text = "Tel. +48  500 000 001, kontakt@strona-testowa.example, ul. Testowa 1, 00-001 Testowo, od 99 zł."

    assert Placeholders.scrub(text, allowed) == text
  end

  test "only values that were not entered are replaced" do
    text = "Tel. 500 000 001 lub 600 100 200."

    assert Placeholders.scrub(text, ["500 000 001"]) == "Tel. 500 000 001 lub [TELEFON]."
  end

  test "ordinary numbers that are not contact data or prices are untouched" do
    text =
      "Od 2019 roku pracują u nas 4 osoby. Odpowiedź ma 3–5 zdań, wymagana jest B kategoria, " <>
        "a kurs trwa 12 miesięcy po 2 godziny. Strona firma.pl. Rozmiar 120 x 80 cm. " <>
        "Prawo jazdy kat. B, auta do 3,5 tony, w latach 2019-2024, od 9:00 do 17:00, pl. 3."

    assert Placeholders.scrub(text, []) == text
  end

  test "existing Placeholders are left as they are" do
    text = "Cena: [CENA], telefon: [TELEFON], [NAZWA FIRMY], [TWOJA-DOMENA], [W SKRÓCIE], [E-MAIL]."

    assert Placeholders.scrub(text, []) == text
  end

  test "bracketed text that is not a Placeholder is scrubbed like any other text" do
    assert Placeholders.scrub("[WSTĘP: 3–5 zdań o firmie, od 80 zł]", []) == "[WSTĘP: 3–5 zdań o firmie, od [CENA]]"
    assert Placeholders.scrub("[TEL 600 100 200]", []) == "[TEL [TELEFON]]"
    assert Placeholders.scrub("[KONTAKT 600-100-200]", []) == "[KONTAKT [TELEFON]]"
    assert Placeholders.scrub("[TELEFON: 600 100 200]", []) == "[TELEFON: [TELEFON]]"

    assert Placeholders.scrub("[UWAGA: dzwoń 600100200, ul. Długa 5, a@b.pl, 80 zł]", []) ==
             "[UWAGA: dzwoń [TELEFON], [ADRES], [E-MAIL], [CENA]]"
  end

  test "bracketed text with digits or a colon is not a Placeholder" do
    refute Placeholders.placeholder?("[TEL 600 100 200]")
    refute Placeholders.placeholder?("[TELEFON: 600 100 200]")
    refute Placeholders.placeholder?("[A:600100200]")
  end

  test "Polish prices in words, lowercase codes, a dash suffix and thousands become one price Placeholder" do
    for {text, scrubbed} <- [
          {"Koszt 80 złotych.", "Koszt [CENA]."},
          {"Koszt 80 złoty.", "Koszt [CENA]."},
          {"Koszt 80 złote.", "Koszt [CENA]."},
          {"Cena od 80 do 120 złotych.", "Cena od [CENA]."},
          {"Cena od 80 do 120 zł.", "Cena od [CENA]."},
          {"Zakres 80-120 zł.", "Zakres [CENA]."},
          {"Koszt 80 pln.", "Koszt [CENA]."},
          {"Koszt pln 80.", "Koszt [CENA]."},
          {"Koszt 30 usd lub 25 eur.", "Koszt [CENA] lub [CENA]."},
          {"Koszt 80,- zł.", "Koszt [CENA]."},
          {"Koszt 1,5 tys. zł.", "Koszt [CENA]."},
          {"Koszt 2 tys zł.", "Koszt [CENA]."}
        ] do
      assert Placeholders.scrub(text, []) == scrubbed, "expected #{inspect(text)} to become #{inspect(scrubbed)}"
    end
  end

  test "a phone with the 0048 country code becomes one phone Placeholder" do
    assert Placeholders.scrub("Tel. 0048 600 100 200.", []) == "Tel. [TELEFON]."
  end

  test "a street whose name starts with a number becomes the address Placeholder" do
    assert Placeholders.scrub("Biuro: ul. 3 Maja 5.", []) == "Biuro: [ADRES]."
    assert Placeholders.scrub("Biuro: al. 11 Listopada 7.", []) == "Biuro: [ADRES]."
  end

  test "an allowed phone keeps only the same digits, with or without the country code" do
    assert Placeholders.scrub("Tel. 600 100 200.", ["+48 600 100 200"]) == "Tel. 600 100 200."
    assert Placeholders.scrub("Tel. +48 600 100 200.", ["600100200"]) == "Tel. +48 600 100 200."
    assert Placeholders.scrub("Tel. 0048 600 100 200.", ["600-100-200"]) == "Tel. 0048 600 100 200."
    assert Placeholders.scrub("Tel. 600 100 200.", ["+48 600 100 2001"]) == "Tel. [TELEFON]."
    assert Placeholders.scrub("Tel. 600 100 201.", ["600 100 200"]) == "Tel. [TELEFON]."
  end

  test "an allowed price keeps only the same amount and currency" do
    assert Placeholders.scrub("Tylko 99 zł.", ["od 99 zł"]) == "Tylko 99 zł."
    assert Placeholders.scrub("Tylko 99 złotych.", ["99 PLN"]) == "Tylko 99 złotych."
    assert Placeholders.scrub("Tylko 50 zł.", ["150 zł"]) == "Tylko [CENA]."
    assert Placeholders.scrub("Tylko 5 zł.", ["od 15 zł"]) == "Tylko [CENA]."
    assert Placeholders.scrub("Tylko 99 EUR.", ["99 zł"]) == "Tylko [CENA]."
  end

  test "an allowed e-mail keeps only the same address in any case" do
    assert Placeholders.scrub("Pisz: JAN.Kowalski@Firma.pl", ["jan.kowalski@firma.pl"]) ==
             "Pisz: JAN.Kowalski@Firma.pl"

    assert Placeholders.scrub("Pisz: kowalski@firma.pl", ["jan.kowalski@firma.pl"]) == "Pisz: [E-MAIL]"
  end

  test "an allowed address keeps only whole parts of the entered address" do
    allowed = ["ul. Długa 15, 80-001 Gdańsk"]

    assert Placeholders.scrub("Biuro: ul. Długa 15.", allowed) == "Biuro: ul. Długa 15."
    assert Placeholders.scrub("Dojazd do 80-001 Gdańsk.", allowed) == "Dojazd do 80-001 Gdańsk."
    assert Placeholders.scrub("Biuro: ul. Długa 1.", allowed) == "Biuro: [ADRES]."
  end

  test "scrubbing twice gives the same text as scrubbing once" do
    text =
      "Dzwoń 600-100-200 lub 0048 600 100 200, pisz biuro@firma.example; cena od 80 do 120 złotych; " <>
        "ul. 3 Maja 5; [TEL 600 100 200]; ul. Długa 5/7."

    once = Placeholders.scrub(text, [])

    assert Placeholders.scrub(once, []) == once
  end

  test "a bracketed upper-case text is a Placeholder" do
    assert Placeholders.placeholder?("[CENA]")
    assert Placeholders.placeholder?("[TWOJA-DOMENA]")
    assert Placeholders.placeholder?("[E-MAIL]")
    assert Placeholders.placeholder?("[NAZWA FIRMY]")
    refute Placeholders.placeholder?("Cena")
    refute Placeholders.placeholder?("[cena]")
    refute Placeholders.placeholder?("Cena [CENA]")
    refute Placeholders.placeholder?(nil)
  end

  test "each missing field has its Placeholder" do
    assert Enum.map(
             [:phone, :email, :address, :price, :business_name, :intro, :answer, :short_answer, :domain],
             &Placeholders.for_field/1
           ) ==
             [
               "[TELEFON]",
               "[E-MAIL]",
               "[ADRES]",
               "[CENA]",
               "[NAZWA FIRMY]",
               "[WSTĘP]",
               "[ODPOWIEDŹ]",
               "[W SKRÓCIE]",
               "[TWOJA-DOMENA]"
             ]

    assert Placeholders.placeholder?(Placeholders.for_field(:anything_else))
  end

  test "a Brief struct has every free-text field scrubbed" do
    brief = %Brief{
      business_name: "Firma 600 100 200",
      title: "Tytuł 600 100 200",
      h1: "Nagłówek od 80 zł",
      breadcrumb: "Start / 80 zł",
      intro: "Wstęp biuro@firma.example",
      cta_label: "Zadzwoń 600 100 200",
      closing_prompt: "Wpadnij na ul. Długa 5/7",
      short_answer: "Krótko: 600-100-200",
      nav_links: ["Cennik od 80 zł", "Kontakt"],
      facts: [%Brief.Fact{label: "Cena 80 zł", value: "80 zł"}],
      sections: [%Brief.Section{question: "Ile kosztuje usługa, 80 zł?", answer: "Koszt 1 200,50 PLN."}]
    }

    assert %Brief{
             business_name: "Firma [TELEFON]",
             title: "Tytuł [TELEFON]",
             h1: "Nagłówek od [CENA]",
             breadcrumb: "Start / [CENA]",
             intro: "Wstęp [E-MAIL]",
             cta_label: "Zadzwoń [TELEFON]",
             closing_prompt: "Wpadnij na [ADRES]",
             short_answer: "Krótko: [TELEFON]",
             nav_links: ["Cennik od [CENA]", "Kontakt"],
             facts: [%Brief.Fact{label: "Cena [CENA]", value: "[CENA]"}],
             sections: [%Brief.Section{question: "Ile kosztuje usługa, [CENA]?", answer: "Koszt [CENA]."}]
           } = Placeholders.scrub_brief(brief, [])
  end

  test "the slug, phrases, Plausible domain and the User's contact details are not scrubbed" do
    brief = %Brief{
      slug: "strona-600-100-200",
      phrases: ["fraza 80 zł"],
      primary_phrase: "fraza 80 zł",
      plausible_domain: "strona-testowa.example",
      phone: "+48 500 000 001",
      email: "kontakt@strona-testowa.example",
      address: "ul. Testowa 1, 00-001 Testowo"
    }

    assert Placeholders.scrub_brief(brief, []) == brief
  end

  test "string-keyed Brief params have every free-text field scrubbed and the entered values kept" do
    params = %{
      "intro" => "Dzwoń 600 100 200 albo +48 500 000 001.",
      "nav_links" => ["Tel. 600 100 200"],
      "facts" => [%{"label" => "Telefon", "value" => "600 100 200"}],
      "sections" => [%{"question" => "Czy 80 zł to dużo?", "answer" => "Pisz: biuro@firma.example"}],
      "slug" => "strona-testowa"
    }

    assert %{
             "intro" => "Dzwoń [TELEFON] albo +48 500 000 001.",
             "nav_links" => ["Tel. [TELEFON]"],
             "facts" => [%{"label" => "Telefon", "value" => "[TELEFON]"}],
             "sections" => [%{"question" => "Czy [CENA] to dużo?", "answer" => "Pisz: [E-MAIL]"}],
             "slug" => "strona-testowa"
           } = Placeholders.scrub_brief(params, ["+48 500 000 001"])
  end

  test "upper-case złoty forms are prices but words that only start with zł are not" do
    for {text, scrubbed} <- [
          {"Koszt 80 ZŁ.", "Koszt [CENA]."},
          {"Koszt 80 Złotych.", "Koszt [CENA]."},
          {"Koszt 80 ZŁOTE.", "Koszt [CENA]."},
          {"Mamy 80 złudzeń.", "Mamy 80 złudzeń."},
          {"Jedziemy 80 Złotoryja.", "Jedziemy 80 Złotoryja."},
          {"Ma 80 ZŁOTNIKÓW.", "Ma 80 ZŁOTNIKÓW."}
        ] do
      assert Placeholders.scrub(text, []) == scrubbed, "expected #{inspect(text)} to become #{inspect(scrubbed)}"
    end
  end

  test "prices written with grouped thousands, ranges and decimals still become one price Placeholder" do
    for {text, scrubbed} <- [
          {"Koszt 1 200 zł.", "Koszt [CENA]."},
          {"Koszt od 1 200 do 1 500 zł.", "Koszt od [CENA]."},
          {"Koszt 80zł80zł.", "Koszt [CENA][CENA]."},
          {"Koszt 12.000,00 zł.", "Koszt [CENA]."}
        ] do
      assert Placeholders.scrub(text, []) == scrubbed, "expected #{inspect(text)} to become #{inspect(scrubbed)}"
    end
  end

  test "scrubbing 50 KB of digits, spaces and brackets finishes quickly" do
    for text <- [
          String.duplicate("1", 50_000),
          String.duplicate("123 ", 12_500),
          String.duplicate("1 2 [3] (45) 6", 3_600)
        ] do
      {microseconds, _scrubbed} = :timer.tc(fn -> Placeholders.scrub(text, []) end)

      assert microseconds < 1_000_000, "took #{div(microseconds, 1000)} ms for #{inspect(binary_part(text, 0, 12))}…"
    end
  end

  test "scrubbing a Brief whose entered phone is 50 KB long finishes quickly" do
    phone = String.duplicate("123 ", 12_500)
    brief = %Brief{phone: phone, intro: "Dzwoń 600 100 200."}

    {microseconds, scrubbed} = :timer.tc(fn -> Placeholders.scrub_brief(brief, [phone]) end)

    assert microseconds < 1_000_000, "took #{div(microseconds, 1000)} ms"
    assert %Brief{phone: ^phone, intro: "Dzwoń [TELEFON]."} = scrubbed
  end

  test "facts and sections given as form index maps are scrubbed and keep their shape" do
    params = %{
      "facts" => %{"0" => %{"label" => "Cena", "value" => "80 zł"}},
      "sections" => %{"0" => %{"question" => "Czy 80 zł to dużo?", "answer" => "Dzwoń 600 100 200."}}
    }

    assert Placeholders.scrub_brief(params, []) == %{
             "facts" => %{"0" => %{"label" => "Cena", "value" => "[CENA]"}},
             "sections" => %{"0" => %{"question" => "Czy [CENA] to dużo?", "answer" => "Dzwoń [TELEFON]."}}
           }
  end

  test "words keeps each Placeholder whole as one word" do
    assert Placeholders.words("Jak działa usługa [NAZWA FIRMY]? Tak.") == [
             "Jak",
             "działa",
             "usługa",
             "[NAZWA FIRMY]?",
             "Tak."
           ]
  end
end
