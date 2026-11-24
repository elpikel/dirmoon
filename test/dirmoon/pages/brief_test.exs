defmodule Dirmoon.Pages.BriefTest do
  use ExUnit.Case, async: true

  import Dirmoon.DataCase, only: [errors_on: 1]

  alias Dirmoon.Pages.Brief

  test "a Brief with an H1 and one question is valid" do
    changeset =
      Brief.changeset(%Brief{}, %{"h1" => "Nagłówek testowy", "sections" => [%{"question" => "Pytanie testowe?"}]})

    assert changeset.valid?
  end

  test "a Brief takes string-keyed params with every field" do
    params = full_params()

    assert {:ok, brief} = %Brief{} |> Brief.changeset(params) |> Ecto.Changeset.apply_action(:insert)

    assert %Brief{
             business_name: "Firma Testowa Alfa",
             slug: "strona-testowa-alfa",
             nav_links: ["Pierwsza", "Druga"],
             fact_tiles: [%Brief.FactTile{label: "Etykieta A", value: "Wartość A"} | _],
             sections: [%Brief.Section{question: "Pytanie testowe pierwsze?", answer: "Odpowiedź testowa."}],
             phrases: ["fraza testowa", "inna fraza testowa"],
             primary_phrase: "fraza testowa",
             plausible_domain: "strona-testowa.example"
           } = brief
  end

  test "a Brief without an H1 is invalid" do
    changeset = Brief.changeset(%Brief{}, %{"sections" => [%{"question" => "Pytanie testowe?"}]})

    assert %{h1: [_]} = errors_on(changeset)
  end

  test "a Brief without sections is invalid" do
    changeset = Brief.changeset(%Brief{}, %{"h1" => "Nagłówek testowy"})

    assert %{sections: [_]} = errors_on(changeset)
  end

  test "a section without a question is invalid" do
    changeset = Brief.changeset(%Brief{}, %{"h1" => "Nagłówek testowy", "sections" => [%{"answer" => "Odpowiedź."}]})

    assert %{sections: [%{question: [_]}]} = errors_on(changeset)
  end

  test "a Brief with more than twelve sections is invalid" do
    sections = Enum.map(1..13, &%{"question" => "Pytanie testowe #{&1}?"})

    changeset = Brief.changeset(%Brief{}, %{"h1" => "Nagłówek testowy", "sections" => sections})

    assert %{sections: [_]} = errors_on(changeset)
  end

  test "a Brief needs exactly three Fact Tiles when it has any" do
    fact_tiles = [%{"label" => "Etykieta A", "value" => "Wartość A"}]

    changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "fact_tiles", fact_tiles))

    assert %{fact_tiles: [_]} = errors_on(changeset)
  end

  test "a Brief has at most three nav links" do
    changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "nav_links", ["A", "B", "C", "D"]))

    assert %{nav_links: [_]} = errors_on(changeset)
  end

  test "a slug with capitals, spaces or diacritics is invalid" do
    for slug <- ["Strona-Testowa", "strona testowa", "strona-żółta", "-strona", "strona--testowa"] do
      changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "slug", slug))

      assert %{slug: [_]} = errors_on(changeset), "expected #{inspect(slug)} to be rejected"
    end
  end

  test "a primary phrase outside the Brief's phrases is invalid" do
    changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "primary_phrase", "fraza spoza listy"))

    assert %{primary_phrase: [_]} = errors_on(changeset)
  end

  test "a plausible domain that is not a bare host is rejected" do
    for domain <- [
          "javascript:alert(1)",
          ~s{strona-testowa.example" onload="alert(1)},
          "https://strona-testowa.example",
          "strona-testowa.example/sciezka",
          "<script>.example",
          "localhost"
        ] do
      changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "plausible_domain", domain))

      assert %{plausible_domain: [_]} = errors_on(changeset), "expected #{inspect(domain)} to be rejected"
    end
  end

  test "clearing the Plausible domain on an existing Brief leaves it empty" do
    brief = existing_brief()

    assert {:ok, cleared} =
             brief |> Brief.changeset(%{"plausible_domain" => ""}) |> Ecto.Changeset.apply_action(:update)

    assert cleared.plausible_domain == nil
    assert Brief.plausible_domain(cleared) == nil
  end

  test "clearing the nav links on an existing Brief leaves an empty list" do
    assert {:ok, cleared} =
             existing_brief() |> Brief.changeset(%{"nav_links" => nil}) |> Ecto.Changeset.apply_action(:update)

    assert cleared.nav_links == []
  end

  test "clearing the phrases on an existing Brief leaves an empty list" do
    assert {:ok, cleared} =
             existing_brief()
             |> Brief.changeset(%{"phrases" => nil, "primary_phrase" => nil})
             |> Ecto.Changeset.apply_action(:update)

    assert cleared.phrases == []
  end

  test "the primary phrase is trimmed like the phrases" do
    params = Map.put(full_params(), "primary_phrase", "  fraza testowa ")

    assert {:ok, brief} = %Brief{} |> Brief.changeset(params) |> Ecto.Changeset.apply_action(:insert)

    assert brief.primary_phrase == "fraza testowa"
  end

  defp existing_brief do
    %Brief{}
    |> Brief.changeset(full_params())
    |> Ecto.Changeset.apply_action!(:insert)
  end

  defp full_params do
    %{
      "business_name" => "Firma Testowa Alfa",
      "title" => "Tytuł testowy",
      "h1" => "Nagłówek testowy",
      "slug" => "strona-testowa-alfa",
      "breadcrumb" => "Start / Test",
      "intro" => "Wstęp testowy.",
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
      "sections" => [%{"question" => "Pytanie testowe pierwsze?", "answer" => "Odpowiedź testowa."}],
      "short_answer" => "Krótka odpowiedź testowa.",
      "phrases" => ["fraza testowa", "inna fraza testowa"],
      "primary_phrase" => "fraza testowa",
      "plausible_domain" => "strona-testowa.example"
    }
  end
end
