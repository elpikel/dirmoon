defmodule Dirmoon.Competition.Check do
  @moduledoc """
  Step 5: who holds Google's top 10 for the run's best Phrases. The
  `serp_phrase_limit` kept Phrases in a Niche with the highest country
  Volume are checked one by one, in that order:

    * the top 10 comes from a fresh shared SERP Snapshot when there is one,
      otherwise it is bought through the run's ledger and stored as a new
      snapshot;
    * the LLM labels each result with a Page Type for this business, through
      the run's ledger; the answer is checked inside the ledger call, so only
      an answer labelling every result is recorded;
    * the labels and the verdict are stored for the run and subscribers get
      the progress.

  A Phrase the run already assessed is not checked again, so a retry
  continues where the last attempt stopped, and a top 10 the run already
  bought is replayed from its ledger rather than taken from the shared
  snapshots. The step stops between Phrases once the run is no longer
  running.
  """

  alias Dirmoon.Competition
  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.DataForSEO
  alias Dirmoon.LLM
  alias Dirmoon.Phrases
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Research
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.Steps

  @step_number Steps.number!(:competition)
  @no_phrases_result "Brak fraz do sprawdzenia"
  @unlabelled_results_error "Model nie oznaczył wszystkich wyników"
  @page_type_names Enum.map(SerpAssessment.page_types(), &Atom.to_string/1)

  @system """
  Jesteś specjalistą SEO. Dostajesz pierwszą stronę wyników Google dla jednej frazy. \
  Każdemu wynikowi przypisujesz dokładnie jeden typ strony z perspektywy opisanej firmy. \
  Odpowiadasz wyłącznie w formacie JSON zgodnym ze schematem.\
  """

  @schema %{
    type: "object",
    properties: %{
      labels: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            position: %{type: "integer"},
            page_type: %{type: "string", enum: @page_type_names}
          },
          required: ["position", "page_type"]
        }
      }
    },
    required: ["labels"]
  }

  @doc """
  Checks the competition for the run's best Phrases.

  Returns `{:ok, %{result: "30 z 30 fraz sprawdzonych", output: output}}` with
  `output` `%{"checked", "total", "reused_snapshots", "weak", "medium", "strong"}`,
  `{:skip, "Brak fraz do sprawdzenia"}` when no kept Phrase is in a Niche,
  `:stopped` when the run stopped meanwhile,
  `{:error, "Model nie oznaczył wszystkich wyników"}`, or the keyword API's
  or LLM's `{:error, reason}`. Phrases assessed before an error stay
  assessed.
  """
  def check(%Run{} = run) do
    case Phrases.top_kept_in_niches(run, phrase_limit()) do
      [] -> {:skip, @no_phrases_result}
      phrases -> check_phrases(run, phrases)
    end
  end

  defp check_phrases(run, phrases) do
    total = length(phrases)
    assessments = Competition.assessments_for_run(run)

    phrases
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {phrase, checked}, {:ok, assessed} ->
      case assess(run, %{phrase: phrase, assessment: Map.get(assessments, phrase.id)}) do
        {:ok, assessment} ->
          broadcast_progress(run, %{phrase: phrase, assessment: assessment, checked: checked, total: total})
          {:cont, {:ok, [assessment | assessed]}}

        stopped_or_error ->
          {:halt, stopped_or_error}
      end
    end)
    |> case do
      {:ok, assessed} -> {:ok, outcome(assessed, total)}
      stopped_or_error -> stopped_or_error
    end
  end

  defp outcome(assessed, total) do
    checked = length(assessed)
    %{result: Competition.checked_line(checked, total), output: output(assessed, total)}
  end

  defp assess(_run, %{assessment: %SerpAssessment{} = assessment}), do: {:ok, assessment}

  defp assess(run, %{phrase: phrase}) do
    with :ok <- ensure_running(run),
         {:ok, %{snapshot: snapshot, reused?: reused?}} <- snapshot(run, phrase),
         {:ok, labels} <- labels(run, %{phrase: phrase, results: snapshot.results}) do
      Competition.store_assessment(run, %{
        keyword_id: phrase.id,
        serp_snapshot_id: snapshot.id,
        labels: labels,
        verdict: Competition.verdict(labels),
        reused_snapshot: reused?
      })
    end
  end

  defp ensure_running(run) do
    if Research.running?(run), do: :ok, else: :stopped
  end

  defp snapshot(run, %Phrase{} = phrase) do
    top10_request = top10_request(run, phrase)

    if Ledger.recorded?(run, top10_request) do
      buy_snapshot(run, %{phrase: phrase, top10_request: top10_request})
    else
      case Competition.fresh_snapshot(phrase.id, run.location_code) do
        nil -> buy_snapshot(run, %{phrase: phrase, top10_request: top10_request})
        snapshot -> {:ok, %{snapshot: snapshot, reused?: true}}
      end
    end
  end

  defp top10_request(run, phrase) do
    %{
      service: "dataforseo",
      operation: "serp_top10",
      request: %{phrase: phrase.phrase, location_code: run.location_code, language_code: run.language_code}
    }
  end

  defp buy_snapshot(run, %{phrase: phrase, top10_request: top10_request}) do
    with {:ok, %{"rows" => results, "raw" => raw, "fetched_at" => fetched_at}} <-
           Ledger.fetch(run, top10_request, fn -> fetch_top10(top10_request.request) end) do
      {:ok, fetched_at, 0} = DateTime.from_iso8601(fetched_at)

      snapshot =
        Competition.store_snapshot(%{
          keyword_id: phrase.id,
          location_code: run.location_code,
          language_code: run.language_code,
          fetched_at: fetched_at,
          results: results,
          raw: raw
        })

      {:ok, %{snapshot: snapshot, reused?: false}}
    end
  end

  defp fetch_top10(request) do
    with {:ok, %{rows: rows, raw: raw, cost: cost}} <- DataForSEO.serp_top10(request) do
      fetched_at = :second |> DateTime.utc_now() |> DateTime.to_iso8601()

      results =
        rows
        |> Enum.sort_by(& &1.position)
        |> Enum.map(&%{"position" => &1.position, "url" => &1.url, "domain" => &1.domain, "title" => &1.title})

      {:ok, %{"rows" => results, "raw" => raw, "fetched_at" => fetched_at}, cost}
    end
  end

  defp labels(_run, %{results: []}), do: {:ok, []}

  defp labels(run, %{phrase: phrase, results: results}) do
    request = label_request(run, %{phrase: phrase.phrase, results: results})

    with {:ok, %{"labels" => labels}} <-
           Ledger.fetch(run, %{service: "llm", operation: "label_serp", request: request}, fn ->
             cleaned_labels(request, results)
           end) do
      {:ok, labels}
    end
  end

  defp cleaned_labels(request, results) do
    with {:ok, answer, cost} <- LLM.structured(request),
         {:ok, labels} <- clean_labels(answer, results),
         do: {:ok, %{"labels" => labels}, cost}
  end

  defp clean_labels(answer, results) do
    positions = MapSet.new(results, & &1["position"])

    labels =
      answer
      |> Map.get("labels")
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and MapSet.member?(positions, &1["position"]) and &1["page_type"] in @page_type_names))
      |> Enum.uniq_by(& &1["position"])
      |> Enum.sort_by(& &1["position"])
      |> Enum.map(&%{"position" => &1["position"], "page_type" => &1["page_type"]})

    if length(labels) == MapSet.size(positions), do: {:ok, labels}, else: {:error, @unlabelled_results_error}
  end

  defp label_request(run, %{phrase: phrase, results: results}) do
    typed_results =
      Enum.map(results, &%{position: &1["position"], url: &1["url"], domain: &1["domain"], title: &1["title"]})

    %{
      task: :label_serp,
      system: @system,
      prompt: prompt(run, %{phrase: phrase, results: typed_results}),
      schema: @schema,
      input: %{phrase: phrase, results: typed_results}
    }
  end

  defp prompt(run, %{phrase: phrase, results: results}) do
    Enum.join(
      [
        "Opis firmy:\n#{run.description}",
        mode_line(run),
        "Fraza: #{phrase}",
        "Każdemu wynikowi przypisz jeden typ strony: " <>
          "direct_competitor (firma oferująca to samo co opisana firma), directory (katalog firm lub porównywarka), " <>
          "forum (forum lub serwis pytań i odpowiedzi), portal (duży portal, serwis ogłoszeniowy lub informacyjny), " <>
          "blog (artykuł lub poradnik). Oznacz wszystkie wyniki, wskazując je przez pozycję.",
        "Wyniki (pozycja. domena: tytuł (adres)):\n" <> Enum.map_join(results, "\n", &serp_result_line/1)
      ],
      "\n\n"
    )
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}), do: "Tryb: istniejąca strona, domena: #{domain}."
  defp mode_line(%Run{mode: :new_idea}), do: "Tryb: nowy pomysł, firma nie ma jeszcze strony."

  defp serp_result_line(%{position: position, url: url, domain: domain, title: title}) do
    "#{position}. #{domain}: #{title || "bez tytułu"} (#{url})"
  end

  defp broadcast_progress(run, %{phrase: phrase, assessment: assessment, checked: checked, total: total}) do
    Research.broadcast_progress(run, %{
      step: @step_number,
      checked: checked,
      total: total,
      phrase: phrase.phrase,
      keyword_id: phrase.id,
      holders: Competition.holders(assessment.labels),
      verdict: assessment.verdict
    })
  end

  defp output(assessments, total) do
    verdict_counts = Enum.frequencies_by(assessments, & &1.verdict)

    %{
      "checked" => length(assessments),
      "total" => total,
      "reused_snapshots" => Enum.count(assessments, & &1.reused_snapshot),
      "weak" => Map.get(verdict_counts, :weak, 0),
      "medium" => Map.get(verdict_counts, :medium, 0),
      "strong" => Map.get(verdict_counts, :strong, 0)
    }
  end

  defp phrase_limit, do: Application.fetch_env!(:dirmoon, :serp_phrase_limit)
end
