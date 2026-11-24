defmodule Dirmoon.Niches.Grouping do
  @moduledoc """
  Step 4: the LLM drops the run's Phrases that are outside the business and
  groups the rest into Niches by search intent. The model sees each Phrase
  as its RunPhrase id, text and country Volume, and answers with ids only, so
  it can never add a Phrase: ids the run doesn't have are ignored. The
  answer is cleaned inside the ledger call, so only a usable answer is
  recorded and a retry asks again.

  Only the `grouping_phrase_limit` Phrases with the highest Volume
  (`config :dirmoon, grouping_phrase_limit:`) are sent; the rest are
  rejected as "poza limitem analizy". A Niche name longer than
  `Niche.max_name_length/0` is cut to that length.
  """

  alias Dirmoon.LLM
  alias Dirmoon.Niches
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Phrases
  alias Dirmoon.Polish
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @no_phrases_error "Brak fraz do pogrupowania"
  @no_niche_error "Model nie zwrócił żadnej niszy"
  @beyond_limit_reason "poza limitem analizy"
  @default_rejection_reason "odrzucona przez model"
  @niche_forms %{one: "nisza", few: "nisze", many: "nisz"}
  @rejected_forms %{one: "fraza odrzucona", few: "frazy odrzucone", many: "fraz odrzuconych"}

  @system """
  Jesteś specjalistą SEO. Dostajesz listę fraz, które ludzie naprawdę wpisują w Google. \
  Odrzucasz frazy spoza działalności firmy, a pozostałe grupujesz w nisze według intencji wyszukiwania. \
  Frazy wskazujesz wyłącznie przez ich identyfikatory z listy i nigdy nie dodajesz nowych fraz. \
  Odpowiadasz wyłącznie w formacie JSON zgodnym ze schematem.\
  """

  @schema %{
    type: "object",
    properties: %{
      niches: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            name: %{type: "string"},
            intent: %{type: "string"},
            reading: %{type: "string"},
            phrase_ids: %{type: "array", items: %{type: "integer"}}
          },
          required: ["name", "intent", "reading", "phrase_ids"]
        }
      },
      rejected: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{phrase_id: %{type: "integer"}, reason: %{type: "string"}},
          required: ["phrase_id", "reason"]
        }
      }
    },
    required: ["niches", "rejected"]
  }

  @doc """
  Filters and groups the run's Phrases and stores the Niches
  (`Dirmoon.Niches.store_grouping/2`). Every Phrase of the run is sent,
  whatever an earlier pass decided about it, because storing decides them
  all again; so a re-run sends the same request and reuses the recorded
  answer.

  Returns `{:ok, %{result: "9 nisz, 137 fraz odrzuconych", output: %{"niches" => 9, "kept" => 263, "rejected" => 137}}}`,
  `{:error, "Brak fraz do pogrupowania"}`, `{:error, "Model nie zwrócił żadnej niszy"}`
  or the LLM's `{:error, reason}`.
  """
  def group(%Run{} = run) do
    {sent_phrases, phrases_beyond_limit} = run |> Phrases.list_for_run() |> Enum.split(phrase_limit())

    with {:ok, phrases} <- phrases_to_send(sent_phrases),
         request = request(run, phrases),
         {:ok, answer} <-
           Ledger.fetch(run, %{service: "llm", operation: "filter_and_group", request: request}, fn ->
             cleaned_grouping(request)
           end),
         {:ok, counts} <- Niches.store_grouping(run, grouping(answer, phrases_beyond_limit)) do
      {:ok, %{result: result_line(counts), output: output(counts)}}
    end
  end

  defp phrases_to_send([]), do: {:error, @no_phrases_error}

  defp phrases_to_send(run_phrases) do
    {:ok,
     Enum.map(run_phrases, fn run_phrase ->
       %{
         id: run_phrase.id,
         phrase: run_phrase.phrase.phrase,
         volume: run_phrase.metrics && run_phrase.metrics.search_volume
       }
     end)}
  end

  defp phrase_limit, do: Application.fetch_env!(:dirmoon, :grouping_phrase_limit)

  defp cleaned_grouping(%{input: %{phrases: phrases}} = request) do
    with {:ok, answer, cost} <- LLM.structured(request),
         {:ok, grouping} <- clean_answer(answer, MapSet.new(phrases, & &1.id)),
         do: {:ok, grouping, cost}
  end

  defp request(run, phrases) do
    %{
      task: :filter_and_group,
      system: @system,
      prompt: prompt(run, phrases),
      schema: @schema,
      input: %{phrases: phrases}
    }
  end

  defp prompt(run, phrases) do
    [
      "Opis firmy:\n#{run.description}",
      mode_line(run),
      priority_services_line(run.priority_services),
      city_line(run.city),
      "Odrzuć frazy, które nie dotyczą tej firmy, i przy każdej podaj krótki powód.",
      "Pozostałe frazy pogrupuj w nisze według intencji wyszukiwania. Każda nisza ma krótką nazwę, " <>
        "intencję i opis w dwóch zdaniach: czego szukają ludzie i kto im dziś odpowiada. " <>
        "Każda fraza trafia do jednej niszy albo do odrzuconych.",
      "Wskazuj frazy wyłącznie przez identyfikatory z listy.",
      "Frazy (identyfikator: fraza (miesięczny wolumen)):\n" <> Enum.map_join(phrases, "\n", &phrase_line/1)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}), do: "Tryb: istniejąca strona, domena: #{domain}."
  defp mode_line(%Run{mode: :new_idea}), do: "Tryb: nowy pomysł, firma nie ma jeszcze strony."

  defp priority_services_line([]), do: nil
  defp priority_services_line(priority_services), do: "Usługi priorytetowe: #{Enum.join(priority_services, ", ")}."

  defp city_line(city) when city in [nil, ""], do: nil
  defp city_line(city), do: "Firma działa w mieście #{city}."

  defp phrase_line(%{id: id, phrase: phrase, volume: nil}), do: "#{id}: #{phrase} (brak danych)"
  defp phrase_line(%{id: id, phrase: phrase, volume: volume}), do: "#{id}: #{phrase} (#{volume})"

  defp clean_answer(answer, sent_ids) do
    case clean_niches(answer, sent_ids) do
      %{niches: []} ->
        {:error, @no_niche_error}

      %{niches: niches, grouped_ids: grouped_ids} ->
        {:ok, %{"niches" => niches, "rejected" => clean_rejected(answer, MapSet.difference(sent_ids, grouped_ids))}}
    end
  end

  defp clean_niches(answer, sent_ids) do
    answer
    |> maps_at("niches")
    |> Enum.reduce(%{niches: [], grouped_ids: MapSet.new()}, fn niche, cleaned ->
      add_niche(cleaned, %{
        name: trimmed(niche["name"]),
        niche: niche,
        phrase_ids: ungrouped_sent_ids(niche["phrase_ids"], %{sent_ids: sent_ids, grouped_ids: cleaned.grouped_ids})
      })
    end)
    |> Map.update!(:niches, &Enum.reverse/1)
  end

  defp ungrouped_sent_ids(phrase_ids, %{sent_ids: sent_ids, grouped_ids: grouped_ids}) do
    phrase_ids
    |> List.wrap()
    |> Enum.filter(&(MapSet.member?(sent_ids, &1) and not MapSet.member?(grouped_ids, &1)))
    |> Enum.uniq()
  end

  defp add_niche(cleaned, %{name: nil}), do: cleaned
  defp add_niche(cleaned, %{phrase_ids: []}), do: cleaned

  defp add_niche(%{niches: niches, grouped_ids: grouped_ids}, %{name: name, niche: niche, phrase_ids: phrase_ids}) do
    %{
      niches: [cleaned_niche(niche, name, phrase_ids) | niches],
      grouped_ids: MapSet.union(grouped_ids, MapSet.new(phrase_ids))
    }
  end

  defp cleaned_niche(niche, name, phrase_ids) do
    %{
      "name" => capped_name(name),
      "intent" => trimmed(niche["intent"]),
      "reading" => trimmed(niche["reading"]),
      "phrase_ids" => phrase_ids
    }
  end

  defp capped_name(name) do
    name
    |> String.codepoints()
    |> Enum.take(Niche.max_name_length())
    |> Enum.join()
  end

  defp clean_rejected(answer, rejectable_ids) do
    answer
    |> maps_at("rejected")
    |> Enum.filter(&MapSet.member?(rejectable_ids, &1["phrase_id"]))
    |> Enum.uniq_by(& &1["phrase_id"])
    |> Enum.map(&%{"phrase_id" => &1["phrase_id"], "reason" => trimmed(&1["reason"]) || @default_rejection_reason})
  end

  defp maps_at(answer, key) do
    answer
    |> Map.get(key)
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp trimmed(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed_text -> trimmed_text
    end
  end

  defp trimmed(_not_text), do: nil

  defp grouping(%{"niches" => niches, "rejected" => rejected}, phrases_beyond_limit) do
    %{
      niches:
        Enum.map(niches, fn niche ->
          %{name: niche["name"], intent: niche["intent"], reading: niche["reading"], phrase_ids: niche["phrase_ids"]}
        end),
      rejected:
        Enum.map(rejected, &%{phrase_id: &1["phrase_id"], reason: &1["reason"]}) ++
          Enum.map(phrases_beyond_limit, &%{phrase_id: &1.id, reason: @beyond_limit_reason})
    }
  end

  defp output(%{niches: niches, kept: kept, rejected: rejected}) do
    %{"niches" => niches, "kept" => kept, "rejected" => rejected}
  end

  defp result_line(%{niches: niches, rejected: rejected}) do
    "#{niches} #{Polish.plural(niches, @niche_forms)}, #{rejected} #{Polish.plural(rejected, @rejected_forms)}"
  end
end
