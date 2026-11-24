defmodule Dirmoon.LLM.Demo do
  @moduledoc """
  Demo Data for the LLM: deterministic, visibly synthetic answers built from
  the request's `input`, at no cost. Used in dev while no provider is chosen.
  Free text starts with "[DEMO]"; it never refers to an id it wasn't given and
  never writes a phone number, price, e-mail or address.
  """

  @behaviour Dirmoon.LLM

  @seed_count 12
  @niche_count 4
  @rejected_every 7
  @brief_phrase_count 6
  @section_count 4
  @minimum_seed_word_length 4
  @page_types ~w(direct_competitor directory forum portal blog)
  @intents ["[DEMO] transakcyjna", "[DEMO] informacyjna", "[DEMO] lokalna", "[DEMO] porównawcza"]
  @fallback_term "usługa"

  @impl Dirmoon.LLM
  def structured(%{task: :seeds, input: input}), do: answer(seeds(input))
  def structured(%{task: :filter_and_group, input: input}), do: answer(filter_and_group(input))
  def structured(%{task: :label_serp, input: input}), do: answer(label_serp(input))
  def structured(%{task: :brief, input: input}), do: answer(brief(input))
  def structured(%{task: task}), do: {:error, {:unknown_llm_task, task}}

  defp answer(output), do: {:ok, output, Decimal.new(0)}

  defp seeds(%{description: description, city: city, priority_services: priority_services}) do
    terms = seed_terms(%{description: description, priority_services: priority_services})

    seeds =
      terms
      |> Enum.flat_map(&with_city_variant(&1, city))
      |> Enum.concat(padding_seeds())
      |> Enum.uniq()
      |> Enum.take(@seed_count)

    %{"seeds" => seeds, "questions" => questions(%{term: List.first(terms, @fallback_term), city: city})}
  end

  defp padding_seeds, do: Enum.map(1..@seed_count, &"demo fraza #{&1}")

  defp seed_terms(%{description: description, priority_services: priority_services}) do
    service_terms = priority_services |> List.wrap() |> Enum.map(&normalise_term/1)

    description_words =
      description
      |> to_string()
      |> String.downcase()
      |> String.split(~r/[^\p{L}]+/u, trim: true)
      |> Enum.filter(&(String.length(&1) >= @minimum_seed_word_length))

    (description_words ++ service_terms)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp with_city_variant(term, city) do
    case normalise_term(city) do
      "" -> [term]
      normalised_city -> [term, "#{term} #{normalised_city}"]
    end
  end

  defp normalise_term(text), do: text |> to_string() |> String.trim() |> String.downcase()

  defp questions(%{term: term, city: city}) do
    place = if normalise_term(city) == "", do: "", else: " w mieście #{city}"

    [
      "[DEMO] Ile kosztuje #{term}?",
      "[DEMO] Gdzie znaleźć #{term}#{place}?",
      "[DEMO] Jak wybrać #{term}?",
      "[DEMO] Czy #{term} jest dostępne w weekend?",
      "[DEMO] Na co zwrócić uwagę, wybierając #{term}?",
      "[DEMO] Jak długo trwa #{term}?"
    ]
  end

  defp filter_and_group(%{phrases: phrases}) do
    {rejected, kept} =
      phrases
      |> Enum.with_index(1)
      |> Enum.split_with(fn {_phrase, position} -> rem(position, @rejected_every) == 0 end)

    %{
      "niches" => kept |> Enum.map(&elem(&1, 0)) |> niches(),
      "rejected" =>
        Enum.map(rejected, fn {phrase, _position} -> %{"phrase_id" => phrase.id, "reason" => "[DEMO] poza ofertą"} end)
    }
  end

  defp niches([]), do: []

  defp niches(phrases) do
    niche_count = min(@niche_count, length(phrases))

    phrases
    |> Enum.with_index()
    |> Enum.group_by(fn {_phrase, index} -> rem(index, niche_count) end, fn {phrase, _index} -> phrase end)
    |> Enum.sort_by(fn {niche_index, _phrases} -> niche_index end)
    |> Enum.map(fn {niche_index, [first_phrase | _rest] = niche_phrases} ->
      %{
        "name" => "[DEMO] Nisza: #{first_phrase.phrase}",
        "intent" => Enum.at(@intents, niche_index),
        "reading" => "[DEMO] Ludzie szukają: #{first_phrase.phrase}",
        "phrase_ids" => Enum.map(niche_phrases, & &1.id)
      }
    end)
  end

  defp label_serp(%{results: results}) do
    %{
      "labels" =>
        Enum.map(results, fn result ->
          %{"position" => result.position, "page_type" => page_type(result.domain)}
        end)
    }
  end

  defp page_type(domain) do
    domain
    |> :erlang.phash2(length(@page_types))
    |> then(&Enum.at(@page_types, &1))
  end

  defp brief(%{niche_name: niche_name, phrases: phrases, questions: questions, city: city}) do
    primary_phrase = List.first(phrases)
    topic = primary_phrase || niche_name
    place = if normalise_term(city) == "", do: "", else: " – #{city}"
    sections = brief_sections(questions)

    %{
      "title" => "[DEMO] #{topic}#{place}",
      "h1" => "[DEMO] #{topic}",
      "slug" => slug(topic),
      "breadcrumb" => "Strona główna / #{niche_name}",
      "intro" => "[DEMO] Wstęp o tym, czego szukają klienci: #{topic}.",
      "cta_label" => "[DEMO] Zapytaj o termin",
      "business_name" => "[NAZWA FIRMY]",
      "facts" => [
        %{"label" => "Cena", "value" => "[CENA]"},
        %{"label" => "Telefon", "value" => "[TELEFON]"},
        %{"label" => "Obszar działania", "value" => "[OBSZAR]"}
      ],
      "sections" => sections,
      "short_answer" => "[DEMO] Krótka odpowiedź: #{hd(sections)["question"]}",
      "phrases" => Enum.take(phrases, @brief_phrase_count),
      "primary_phrase" => primary_phrase
    }
  end

  defp brief_sections(questions) do
    questions
    |> Enum.concat([
      "[DEMO] Jak wygląda współpraca?",
      "[DEMO] Dla kogo jest ta usługa?",
      "[DEMO] Jak się przygotować?",
      "[DEMO] Co wyróżnia tę firmę?"
    ])
    |> Enum.take(@section_count)
    |> Enum.map(&%{"question" => &1, "answer" => "[DEMO] Odpowiedź uzupełni właściciel firmy."})
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace("ł", "l")
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.split(~r/[\s-]+/, trim: true)
    |> Enum.join("-")
  end
end
