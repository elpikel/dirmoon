defmodule Dirmoon.LLM.Demo do
  @moduledoc """
  Demo Data for the LLM: deterministic, visibly synthetic answers built from
  the request's `input`, at no cost. Used in dev while no provider is chosen.
  Free text starts with the Demo Data marker, `Dirmoon.demo_marker/0`; it never refers to an id it wasn't given and
  never writes a phone number, price, e-mail or address: it finds no
  Competitor Offers on any page. It does not match a site's pages to
  Niches nor describe a site from its home page (both
  `{:error, :not_in_demo_data}`): any answer, even "no page matches", would
  read as a fact about the owner's real site.

  What the owner reads (Niche names, intents, Readings, rejection reasons)
  is English; Seeds, questions and Brief text are Polish whatever the run's
  Market.
  """

  @behaviour Dirmoon.LLM

  @marker Dirmoon.demo_marker()
  @seed_count 12
  @niche_count 4
  @rejected_every 7
  @brief_phrase_count 6
  @section_count 4
  @minimum_seed_word_length 4
  @page_types ~w(direct_competitor directory forum portal blog)
  @intents ["#{@marker} transactional", "#{@marker} informational", "#{@marker} local", "#{@marker} comparison"]
  @fallback_word "usługa"

  @impl Dirmoon.LLM
  def structured(%{task: :seeds, input: input}), do: answer(seeds(input))
  def structured(%{task: :filter_and_group, input: input}), do: answer(filter_and_group(input))
  def structured(%{task: :label_serp, input: input}), do: answer(label_serp(input))
  def structured(%{task: :brief, input: input}), do: answer(brief(input))
  def structured(%{task: :competitor_prices}), do: answer(%{"offers" => []})
  def structured(%{task: :match_pages}), do: {:error, :not_in_demo_data}
  def structured(%{task: :describe_site}), do: {:error, :not_in_demo_data}
  def structured(%{task: task}), do: {:error, {:unknown_llm_task, task}}

  defp answer(output), do: {:ok, output, Decimal.new(0)}

  defp seeds(%{description: description, city: city, priority_services: priority_services}) do
    words = seed_words(%{description: description, priority_services: priority_services})

    seeds =
      words
      |> Enum.flat_map(&with_city_variant(&1, city))
      |> Enum.concat(padding_seeds())
      |> Enum.uniq()
      |> Enum.take(@seed_count)

    %{"seeds" => seeds, "questions" => questions(%{word: List.first(words, @fallback_word), city: city})}
  end

  defp padding_seeds, do: Enum.map(1..@seed_count, &"demo fraza #{&1}")

  defp seed_words(%{description: description, priority_services: priority_services}) do
    service_words = priority_services |> List.wrap() |> Enum.map(&normalise_text/1)

    description_words =
      description
      |> to_string()
      |> String.downcase()
      |> String.split(~r/[^\p{L}]+/u, trim: true)
      |> Enum.filter(&(String.length(&1) >= @minimum_seed_word_length))

    (description_words ++ service_words)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp with_city_variant(word, city) do
    case normalise_text(city) do
      "" -> [word]
      normalised_city -> [word, "#{word} #{normalised_city}"]
    end
  end

  defp normalise_text(text), do: text |> to_string() |> String.trim() |> String.downcase()

  defp questions(%{word: word, city: city}) do
    place = if normalise_text(city) == "", do: "", else: " w mieście #{city}"

    [
      "#{@marker} Ile kosztuje #{word}?",
      "#{@marker} Gdzie znaleźć #{word}#{place}?",
      "#{@marker} Jak wybrać #{word}?",
      "#{@marker} Czy #{word} jest dostępne w weekend?",
      "#{@marker} Na co zwrócić uwagę, wybierając #{word}?",
      "#{@marker} Jak długo trwa #{word}?"
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
        Enum.map(rejected, fn {phrase, _position} ->
          %{"phrase_id" => phrase.id, "reason" => "#{@marker} outside the offer"}
        end)
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
        "name" => "#{@marker} Topic: #{first_phrase.phrase}",
        "intent" => Enum.at(@intents, niche_index),
        "reading" => "#{@marker} People search for: #{first_phrase.phrase}",
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
    place = if normalise_text(city) == "", do: "", else: " – #{city}"
    sections = brief_sections(questions)

    %{
      "title" => "#{@marker} #{topic}#{place}",
      "h1" => "#{@marker} #{topic}",
      "slug" => slug(topic),
      "intro" => "#{@marker} Wstęp o tym, czego szukają klienci: #{topic}.",
      "business_name" => "[BUSINESS NAME]",
      "sections" => sections,
      "short_answer" => "#{@marker} Krótka odpowiedź: #{hd(sections)["question"]}",
      "phrases" => Enum.take(phrases, @brief_phrase_count),
      "primary_phrase" => primary_phrase
    }
  end

  defp brief_sections(questions) do
    questions
    |> Enum.concat([
      "#{@marker} Jak wygląda współpraca?",
      "#{@marker} Dla kogo jest ta usługa?",
      "#{@marker} Jak się przygotować?",
      "#{@marker} Co wyróżnia tę firmę?"
    ])
    |> Enum.take(@section_count)
    |> Enum.map(&%{"question" => &1, "answer" => "#{@marker} Odpowiedź uzupełni właściciel firmy."})
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
