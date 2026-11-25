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
             email: "kontakt@strona-testowa.example",
             sections: [%Brief.Section{question: "Pytanie testowe pierwsze?", answer: "Odpowiedź testowa."}],
             phrases: ["fraza testowa", "inna fraza testowa"],
             primary_phrase: "fraza testowa"
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

  test "an e-mail that is not shaped like an address is rejected" do
    for email <- ["kontakt", "kontakt@strona", "kontakt @strona-testowa.example", "<kontakt>@strona-testowa.example"] do
      changeset = Brief.changeset(%Brief{}, Map.put(full_params(), "email", email))

      assert %{email: [_]} = errors_on(changeset), "expected #{inspect(email)} to be rejected"
    end
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
      "intro" => "Wstęp testowy.",
      "phone" => "+48 500 000 001",
      "email" => "kontakt@strona-testowa.example",
      "address" => "ul. Testowa 1, 00-001 Testowo",
      "sections" => [%{"question" => "Pytanie testowe pierwsze?", "answer" => "Odpowiedź testowa."}],
      "short_answer" => "Krótka odpowiedź testowa.",
      "phrases" => ["fraza testowa", "inna fraza testowa"],
      "primary_phrase" => "fraza testowa"
    }
  end
end
