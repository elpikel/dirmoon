defmodule Dirmoon.Pages.BriefWriter do
  @moduledoc """
  Step 8: the LLM writes the Brief and the content for the run's page that
  is `:writing` (the Niche the User chose last), from the Niche's kept
  Phrases and the customer questions Step 1 found.

  The answer is cleaned inside the ledger call, so only a usable Brief is
  recorded and a retry asks again: invented phones, prices, e-mails and
  addresses become Placeholders, the contact fields the User owns (phone,
  e-mail, address, business name, Plausible domain) are dropped, and only
  Phrases of the chosen Niche are kept, with the primary one among them.
  """

  alias Dirmoon.LLM
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.Placeholders
  alias Dirmoon.Phrases
  alias Dirmoon.Research
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.Steps

  @no_page_result "Brak strony do napisania"
  @invalid_brief_error "Model zwrócił niepoprawny brief"
  @phrase_limit 40
  @seeds_step Steps.number!(:seeds)
  @written_keys ~w(title h1 slug breadcrumb intro cta_label fact_tiles sections short_answer phrases primary_phrase)

  @system """
  Jesteś copywriterem SEO. Piszesz plan i treść jednej strony dla wybranej niszy. \
  Nigdy nie podajesz cen, numerów telefonów, adresów, adresów e-mail ani faktów o firmie. \
  W miejscu takiej wartości wpisujesz znacznik w nawiasach kwadratowych wielkimi literami, np. [CENA], [TELEFON]. \
  Odpowiadasz wyłącznie w formacie JSON zgodnym ze schematem.\
  """

  @schema %{
    type: "object",
    properties: %{
      title: %{type: "string"},
      h1: %{type: "string"},
      slug: %{type: "string"},
      breadcrumb: %{type: "string"},
      intro: %{type: "string"},
      cta_label: %{type: "string"},
      fact_tiles: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{label: %{type: "string"}, value: %{type: "string"}},
          required: ["label", "value"]
        }
      },
      sections: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{question: %{type: "string"}, answer: %{type: "string"}},
          required: ["question", "answer"]
        }
      },
      short_answer: %{type: "string"},
      phrases: %{type: "array", items: %{type: "string"}},
      primary_phrase: %{type: "string"}
    },
    required: ~w(title h1 slug breadcrumb intro cta_label fact_tiles sections short_answer phrases primary_phrase)
  }

  @doc """
  Writes and stores the Brief of the run's `:writing` page and marks it
  `:ready` (`Dirmoon.Pages.store_brief/2`).

  Returns `{:ok, %{result: "Brief gotowy: <H1>", output: %{"page_id" => id}}}`,
  `{:skip, "Brak strony do napisania"}` when no page is `:writing`,
  `{:error, "Model zwrócił niepoprawny brief"}` or the LLM's `{:error, reason}`.
  """
  def write(%Run{} = run) do
    case Pages.writing_page_for_run(run) do
      %Page{} = page -> write_page(run, page)
      nil -> {:skip, @no_page_result}
    end
  end

  defp write_page(run, %Page{niche: niche} = page) do
    request = request(run, %{niche_name: niche.name, phrases: niche_phrases(run, niche), questions: questions(run)})

    with {:ok, brief_params} <-
           Ledger.fetch(run, %{service: "llm", operation: "brief", request: request}, fn -> cleaned_brief(request) end),
         {:ok, %Page{brief: brief} = written_page} <- Pages.store_brief(page, brief_params) do
      {:ok, %{result: "Brief gotowy: #{brief.h1}", output: %{"page_id" => written_page.id}}}
    else
      {:error, %Ecto.Changeset{}} -> {:error, @invalid_brief_error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp niche_phrases(run, niche) do
    run
    |> Phrases.list_for_run()
    |> Enum.filter(&(&1.status == :kept and &1.cluster_id == niche.id))
    |> Enum.take(@phrase_limit)
    |> Enum.map(& &1.phrase.phrase)
  end

  defp questions(run) do
    case Research.step_output(run, @seeds_step) do
      {:ok, %{"questions" => questions}} when is_list(questions) -> questions
      _no_questions -> []
    end
  end

  defp request(run, %{niche_name: niche_name, phrases: phrases, questions: questions}) do
    %{
      task: :brief,
      system: @system,
      prompt: prompt(run, %{niche_name: niche_name, phrases: phrases, questions: questions}),
      schema: @schema,
      input: %{
        niche_name: niche_name,
        phrases: phrases,
        questions: questions,
        business_description: run.description,
        city: run.city
      }
    }
  end

  defp prompt(run, %{niche_name: niche_name, phrases: phrases, questions: questions}) do
    [
      "Opis firmy:\n#{run.description}",
      mode_line(run),
      city_line(run.city),
      "Nisza: #{niche_name}.",
      "Napisz brief i treść JEDNEJ strony, która ma trafić na frazy tej niszy: tytuł strony, H1, slug adresu " <>
        "(małe litery bez polskich znaków, słowa rozdzielone myślnikami), okruszki, wstęp w dwóch zdaniach, " <>
        "etykietę przycisku, trzy kafelki z faktami (etykieta i wartość jako znacznik, np. [CENA]), " <>
        "od 4 do 6 sekcji jako pytania klientów z odpowiedziami po 3–5 zdań, " <>
        "jednozdaniową krótką odpowiedź na pierwsze pytanie oraz frazy do pokrycia z jedną główną.",
      "Nigdy nie podawaj cen, numerów telefonów, adresów, adresów e-mail ani faktów o firmie. " <>
        "W miejscu takiej wartości wpisz znacznik w nawiasach kwadratowych wielkimi literami, np. [CENA], [TELEFON].",
      "Frazy do pokrycia wybierz wyłącznie z listy fraz niszy.",
      "Frazy niszy (od najczęściej wyszukiwanych):\n" <> Enum.join(phrases, "\n"),
      questions_line(questions)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}) do
    "Tryb: istniejąca strona, domena: #{domain}. Strona trafi na tę domenę. " <>
      "Odpowiedzi prawne, medyczne i finansowe sprawdzi właściciel firmy przed publikacją."
  end

  defp mode_line(%Run{mode: :new_idea}), do: "Tryb: nowy pomysł, firma nie ma jeszcze strony."

  defp city_line(city) when city in [nil, ""], do: nil
  defp city_line(city), do: "Firma działa w mieście #{city}."

  defp questions_line([]), do: nil
  defp questions_line(questions), do: "Pytania klientów:\n" <> Enum.join(questions, "\n")

  defp cleaned_brief(%{input: %{phrases: niche_phrases}} = request) do
    with {:ok, answer, cost} <- LLM.structured(request),
         {:ok, brief_params} <- clean_answer(answer, niche_phrases),
         do: {:ok, brief_params, cost}
  end

  defp clean_answer(answer, niche_phrases) when is_map(answer) do
    brief_params =
      answer
      |> Map.take(@written_keys)
      |> Placeholders.scrub_brief([])
      |> keep_niche_phrases(niche_phrases)

    if Brief.changeset(%Brief{}, brief_params).valid?, do: {:ok, brief_params}, else: {:error, @invalid_brief_error}
  end

  defp clean_answer(_answer, _niche_phrases), do: {:error, @invalid_brief_error}

  defp keep_niche_phrases(brief_params, niche_phrases) do
    niche_phrases_by_key = Map.new(niche_phrases, &{phrase_key(&1), &1})

    kept_phrases =
      brief_params
      |> Map.get("phrases")
      |> List.wrap()
      |> Enum.flat_map(&matching_niche_phrase(&1, niche_phrases_by_key))
      |> Enum.uniq()

    primary_phrase =
      brief_params
      |> Map.get("primary_phrase")
      |> matching_niche_phrase(niche_phrases_by_key)
      |> Enum.find(&(&1 in kept_phrases))

    Map.merge(brief_params, %{"phrases" => kept_phrases, "primary_phrase" => primary_phrase || List.first(kept_phrases)})
  end

  defp matching_niche_phrase(phrase, niche_phrases_by_key) when is_binary(phrase) do
    case Map.fetch(niche_phrases_by_key, phrase_key(phrase)) do
      {:ok, niche_phrase} -> [niche_phrase]
      :error -> []
    end
  end

  defp matching_niche_phrase(_not_a_phrase, _niche_phrases_by_key), do: []

  defp phrase_key(phrase) do
    phrase
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end
end
