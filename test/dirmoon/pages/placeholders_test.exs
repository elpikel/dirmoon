defmodule Dirmoon.Pages.PlaceholdersTest do
  use ExUnit.Case, async: true

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Placeholders

  test "an invented phone number becomes the phone Placeholder" do
    for phone <- ["+48 600 100 200", "600-100-200", "600100200", "58 123 45 67", "(58) 123 45 67"] do
      assert Placeholders.scrub("Zadzwoń: #{phone} w dni robocze.", []) == "Zadzwoń: [PHONE] w dni robocze.",
             "expected #{inspect(phone)} to be replaced"
    end
  end

  test "an invented price becomes the price Placeholder" do
    assert Placeholders.scrub("Testowa usługa od 80 zł za dzień.", []) == "Testowa usługa od [PRICE] za dzień."
    assert Placeholders.scrub("Pakiet testowy: 1 200,50 PLN brutto.", []) == "Pakiet testowy: [PRICE] brutto."
    assert Placeholders.scrub("Wersja testowa za €15.", []) == "Wersja testowa za [PRICE]."
    assert Placeholders.scrub("Opłata 25 EUR lub $30 lub 30 USD.", []) == "Opłata [PRICE] lub [PRICE] lub [PRICE]."
    assert Placeholders.scrub("Zakres 80–120 zł.", []) == "Zakres [PRICE]."
  end

  test "an invented e-mail address becomes the e-mail Placeholder" do
    assert Placeholders.scrub("Pisz na biuro@firma.example dziś.", []) == "Pisz na [E-MAIL] dziś."
  end

  test "an invented street address becomes the address Placeholder" do
    assert Placeholders.scrub("Biuro: ul. Długa 5/7, 80-001 Gdańsk.", []) == "Biuro: [ADDRESS]."
    assert Placeholders.scrub("Odbiór przy al. Testowa Aleja 12.", []) == "Odbiór przy [ADDRESS]."
    assert Placeholders.scrub("Siedziba: os. Próbne 4a.", []) == "Siedziba: [ADDRESS]."
    assert Placeholders.scrub("Dojazd do 80-001 Gdańsk jest prosty.", []) == "Dojazd do [ADDRESS] jest prosty."
  end

  test "values the User entered are kept" do
    allowed = ["+48 500 000 001", "kontakt@strona-testowa.example", "ul. Testowa 1, 00-001 Testowo", "od 99 zł"]

    text = "Tel. +48  500 000 001, kontakt@strona-testowa.example, ul. Testowa 1, 00-001 Testowo, od 99 zł."

    assert Placeholders.scrub(text, allowed) == text
  end

  test "only values that were not entered are replaced" do
    text = "Tel. 500 000 001 lub 600 100 200."

    assert Placeholders.scrub(text, ["500 000 001"]) == "Tel. 500 000 001 lub [PHONE]."
  end

  test "ordinary numbers that are not contact data or prices are untouched" do
    text =
      "Od 2019 roku pracują u nas 4 osoby. Odpowiedź ma 3–5 zdań, wymagana jest B kategoria, " <>
        "a kurs trwa 12 miesięcy po 2 godziny. Strona firma.pl. Rozmiar 120 x 80 cm. " <>
        "Prawo jazdy kat. B, auta do 3,5 tony, w latach 2019-2024, od 9:00 do 17:00, pl. 3."

    assert Placeholders.scrub(text, []) == text
  end

  test "existing Placeholders are left as they are" do
    text = "Cena: [PRICE], telefon: [PHONE], [BUSINESS NAME], [YOUR-DOMAIN], [SHORT ANSWER], [E-MAIL]."

    assert Placeholders.scrub(text, []) == text
  end

  test "bracketed text that is not a Placeholder is scrubbed like any other text" do
    assert Placeholders.scrub("[WSTĘP: 3–5 zdań o firmie, od 80 zł]", []) == "[WSTĘP: 3–5 zdań o firmie, od [PRICE]]"
    assert Placeholders.scrub("[TEL 600 100 200]", []) == "[TEL [PHONE]]"
    assert Placeholders.scrub("[KONTAKT 600-100-200]", []) == "[KONTAKT [PHONE]]"
    assert Placeholders.scrub("[TELEFON: 600 100 200]", []) == "[TELEFON: [PHONE]]"

    assert Placeholders.scrub("[UWAGA: dzwoń 600100200, ul. Długa 5, a@b.pl, 80 zł]", []) ==
             "[UWAGA: dzwoń [PHONE], [ADDRESS], [E-MAIL], [PRICE]]"
  end

  test "bracketed text with digits or a colon is not a Placeholder" do
    refute Placeholders.placeholder?("[TEL 600 100 200]")
    refute Placeholders.placeholder?("[TELEFON: 600 100 200]")
    refute Placeholders.placeholder?("[A:600100200]")
  end

  test "Polish prices in words, lowercase codes, a dash suffix and thousands become one price Placeholder" do
    for {text, scrubbed} <- [
          {"Koszt 80 złotych.", "Koszt [PRICE]."},
          {"Koszt 80 złoty.", "Koszt [PRICE]."},
          {"Koszt 80 złote.", "Koszt [PRICE]."},
          {"Cena od 80 do 120 złotych.", "Cena od [PRICE]."},
          {"Cena od 80 do 120 zł.", "Cena od [PRICE]."},
          {"Zakres 80-120 zł.", "Zakres [PRICE]."},
          {"Koszt 80 pln.", "Koszt [PRICE]."},
          {"Koszt pln 80.", "Koszt [PRICE]."},
          {"Koszt 30 usd lub 25 eur.", "Koszt [PRICE] lub [PRICE]."},
          {"Koszt 80,- zł.", "Koszt [PRICE]."},
          {"Koszt 1,5 tys. zł.", "Koszt [PRICE]."},
          {"Koszt 2 tys zł.", "Koszt [PRICE]."}
        ] do
      assert Placeholders.scrub(text, []) == scrubbed, "expected #{inspect(text)} to become #{inspect(scrubbed)}"
    end
  end

  test "a phone with the 0048 country code becomes one phone Placeholder" do
    assert Placeholders.scrub("Tel. 0048 600 100 200.", []) == "Tel. [PHONE]."
  end

  test "a street whose name starts with a number becomes the address Placeholder" do
    assert Placeholders.scrub("Biuro: ul. 3 Maja 5.", []) == "Biuro: [ADDRESS]."
    assert Placeholders.scrub("Biuro: al. 11 Listopada 7.", []) == "Biuro: [ADDRESS]."
  end

  test "an allowed phone keeps only the same digits, with or without the country code" do
    assert Placeholders.scrub("Tel. 600 100 200.", ["+48 600 100 200"]) == "Tel. 600 100 200."
    assert Placeholders.scrub("Tel. +48 600 100 200.", ["600100200"]) == "Tel. +48 600 100 200."
    assert Placeholders.scrub("Tel. 0048 600 100 200.", ["600-100-200"]) == "Tel. 0048 600 100 200."
    assert Placeholders.scrub("Tel. 600 100 200.", ["+48 600 100 2001"]) == "Tel. [PHONE]."
    assert Placeholders.scrub("Tel. 600 100 201.", ["600 100 200"]) == "Tel. [PHONE]."
  end

  test "an allowed price keeps only the same amount and currency" do
    assert Placeholders.scrub("Tylko 99 zł.", ["od 99 zł"]) == "Tylko 99 zł."
    assert Placeholders.scrub("Tylko 99 złotych.", ["99 PLN"]) == "Tylko 99 złotych."
    assert Placeholders.scrub("Tylko 50 zł.", ["150 zł"]) == "Tylko [PRICE]."
    assert Placeholders.scrub("Tylko 5 zł.", ["od 15 zł"]) == "Tylko [PRICE]."
    assert Placeholders.scrub("Tylko 99 EUR.", ["99 zł"]) == "Tylko [PRICE]."
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
    assert Placeholders.scrub("Biuro: ul. Długa 1.", allowed) == "Biuro: [ADDRESS]."
  end

  test "scrubbing twice gives the same text as scrubbing once" do
    text =
      "Dzwoń 600-100-200 lub 0048 600 100 200, pisz biuro@firma.example; cena od 80 do 120 złotych; " <>
        "ul. 3 Maja 5; [TEL 600 100 200]; ul. Długa 5/7."

    once = Placeholders.scrub(text, [])

    assert Placeholders.scrub(once, []) == once
  end

  test "a bracketed upper-case text is a Placeholder" do
    assert Placeholders.placeholder?("[PRICE]")
    assert Placeholders.placeholder?("[YOUR-DOMAIN]")
    assert Placeholders.placeholder?("[E-MAIL]")
    assert Placeholders.placeholder?("[BUSINESS NAME]")
    refute Placeholders.placeholder?("Cena")
    refute Placeholders.placeholder?("[cena]")
    refute Placeholders.placeholder?("Cena [PRICE]")
    refute Placeholders.placeholder?(nil)
  end

  test "a Brief struct has every free-text field scrubbed" do
    brief = %Brief{
      business_name: "Firma 600 100 200",
      title: "Tytuł 600 100 200",
      h1: "Nagłówek od 80 zł",
      intro: "Wstęp biuro@firma.example, ul. Długa 5/7",
      short_answer: "Krótko: 600-100-200",
      sections: [%Brief.Section{question: "Ile kosztuje usługa, 80 zł?", answer: "Koszt 1 200,50 PLN."}]
    }

    assert %Brief{
             business_name: "Firma [PHONE]",
             title: "Tytuł [PHONE]",
             h1: "Nagłówek od [PRICE]",
             intro: "Wstęp [E-MAIL], [ADDRESS]",
             short_answer: "Krótko: [PHONE]",
             sections: [%Brief.Section{question: "Ile kosztuje usługa, [PRICE]?", answer: "Koszt [PRICE]."}]
           } = Placeholders.scrub_brief(brief, [])
  end

  test "the slug, phrases and the User's contact details are not scrubbed" do
    brief = %Brief{
      slug: "strona-600-100-200",
      phrases: ["fraza 80 zł"],
      primary_phrase: "fraza 80 zł",
      phone: "+48 500 000 001",
      email: "kontakt@strona-testowa.example",
      address: "ul. Testowa 1, 00-001 Testowo"
    }

    assert Placeholders.scrub_brief(brief, []) == brief
  end

  test "string-keyed Brief params have every free-text field scrubbed and the entered values kept" do
    params = %{
      "intro" => "Dzwoń 600 100 200 albo +48 500 000 001.",
      "sections" => [%{"question" => "Czy 80 zł to dużo?", "answer" => "Pisz: biuro@firma.example"}],
      "slug" => "strona-testowa"
    }

    assert %{
             "intro" => "Dzwoń [PHONE] albo +48 500 000 001.",
             "sections" => [%{"question" => "Czy [PRICE] to dużo?", "answer" => "Pisz: [E-MAIL]"}],
             "slug" => "strona-testowa"
           } = Placeholders.scrub_brief(params, ["+48 500 000 001"])
  end

  test "atom-keyed Brief params have their free-text fields scrubbed and keep their keys" do
    params = %{
      intro: "Dzwoń 600 100 200.",
      sections: [%{question: "Czy 80 zł to dużo?", answer: "Tak."}]
    }

    assert Placeholders.scrub_brief(params, []) == %{
             intro: "Dzwoń [PHONE].",
             sections: [%{question: "Czy [PRICE] to dużo?", answer: "Tak."}]
           }
  end

  test "Brief params without sections have their text scrubbed and gain no sections" do
    params = %{"title" => nil, "intro" => "Tel. 600 100 200"}

    assert Placeholders.scrub_brief(params, []) == %{"title" => nil, "intro" => "Tel. [PHONE]"}
  end

  test "an allowed value given as a number is compared as its text" do
    assert Placeholders.scrub("Dzwoń 600 100 200 albo 600 100 300.", [600_100_200]) ==
             "Dzwoń 600 100 200 albo [PHONE]."
  end

  test "upper-case złoty forms are prices but words that only start with zł are not" do
    for {text, scrubbed} <- [
          {"Koszt 80 ZŁ.", "Koszt [PRICE]."},
          {"Koszt 80 Złotych.", "Koszt [PRICE]."},
          {"Koszt 80 ZŁOTE.", "Koszt [PRICE]."},
          {"Mamy 80 złudzeń.", "Mamy 80 złudzeń."},
          {"Jedziemy 80 Złotoryja.", "Jedziemy 80 Złotoryja."},
          {"Ma 80 ZŁOTNIKÓW.", "Ma 80 ZŁOTNIKÓW."}
        ] do
      assert Placeholders.scrub(text, []) == scrubbed, "expected #{inspect(text)} to become #{inspect(scrubbed)}"
    end
  end

  test "prices written with grouped thousands, ranges and decimals still become one price Placeholder" do
    for {text, scrubbed} <- [
          {"Koszt 1 200 zł.", "Koszt [PRICE]."},
          {"Koszt od 1 200 do 1 500 zł.", "Koszt od [PRICE]."},
          {"Koszt 80zł80zł.", "Koszt [PRICE][PRICE]."},
          {"Koszt 12.000,00 zł.", "Koszt [PRICE]."}
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
    assert %Brief{phone: ^phone, intro: "Dzwoń [PHONE]."} = scrubbed
  end

  test "sections given as form index maps are scrubbed and keep their shape" do
    params = %{
      "sections" => %{"0" => %{"question" => "Czy 80 zł to dużo?", "answer" => "Dzwoń 600 100 200."}}
    }

    assert Placeholders.scrub_brief(params, []) == %{
             "sections" => %{"0" => %{"question" => "Czy [PRICE] to dużo?", "answer" => "Dzwoń [PHONE]."}}
           }
  end
end
