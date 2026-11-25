defmodule Dirmoon.Pages.BriefWriter do
  @moduledoc """
  Step 8: the LLM writes the Brief for the run's page that is `:writing`
  (the Niche the User chose last), from the Niche's kept Phrases and the
  customer questions Step 1 found.

  The answer is cleaned inside the ledger call, so only a usable Brief is
  recorded and a retry asks again: invented phones, prices, e-mails and
  addresses become Placeholders, the contact fields the User owns (phone,
  e-mail, address, business name) are dropped, and only
  Phrases of the chosen Niche are kept, with the primary one among them.

  The Brief's text is for the market's customers, so the LLM
  writes them in the run's market language.
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

  @no_page_result "No page to write"
  @invalid_brief_error "The model returned an invalid brief"
  @phrase_limit 40
  @seeds_step Steps.number!(:seeds)
  @written_keys ~w(title h1 slug intro sections short_answer phrases primary_phrase)

  @system """
  You are an SEO copywriter. You write the brief of one page for a chosen niche: its plan and its text, \
  which the business owner hands to whoever builds their site. \
  You write the text in the language of the business's market, for its customers. \
  You never give prices, phone numbers, addresses, e-mail addresses or facts about the business. \
  In place of such a value you write a tag in square brackets in capital letters, e.g. [PRICE], [PHONE]. \
  You answer only in JSON that matches the schema.\
  """

  @schema %{
    type: "object",
    properties: %{
      title: %{type: "string"},
      h1: %{type: "string"},
      slug: %{type: "string"},
      intro: %{type: "string"},
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
    required: ~w(title h1 slug intro sections short_answer phrases primary_phrase)
  }

  @doc """
  Writes and stores the Brief of the run's `:writing` page and marks it
  `:ready` (`Dirmoon.Pages.store_brief/2`).

  Returns `{:ok, %{result: "Brief ready: <H1>", output: %{"page_id" => id}}}`,
  `{:skip, "No page to write"}` when no page is `:writing`,
  `{:error, "The model returned an invalid brief"}` or the LLM's `{:error, reason}`.
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
      {:ok, %{result: "Brief ready: #{brief.h1}", output: %{"page_id" => written_page.id}}}
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
      "Business description:\n#{run.description}",
      mode_line(run),
      city_line(run.city),
      "Niche (named in English for the owner): #{niche_name}.",
      "Write every text of the brief in #{Run.language_name(run)}, the language of the business's market: " <>
        "the page is for its customers. Keep the tags in square brackets exactly as they are, in English.",
      "Write the brief of ONE page that should rank for this niche's phrases: the page title, H1, " <>
        "the address slug (lower case without diacritics, words separated by hyphens), a two-sentence intro, " <>
        "4 to 6 sections as customer questions with answers of 3–5 sentences each, " <>
        "a one-sentence short answer to the first question, and the phrases to cover with one primary phrase.",
      "Never give prices, phone numbers, addresses, e-mail addresses or facts about the business. " <>
        "In place of such a value write a tag in square brackets in capital letters, e.g. [PRICE], [PHONE].",
      "Pick the phrases to cover only from the niche's phrase list.",
      "The niche's phrases (most searched first):\n" <> Enum.join(phrases, "\n"),
      questions_line(questions)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}) do
    "Mode: existing site, domain: #{domain}. The page will go on this domain. " <>
      "The business owner will check legal, medical and financial answers before publishing."
  end

  defp mode_line(%Run{mode: :new_idea}), do: "Mode: new idea, the business has no site yet."

  defp city_line(city) when city in [nil, ""], do: nil
  defp city_line(city), do: "The business works in the city of #{city}."

  defp questions_line([]), do: nil
  defp questions_line(questions), do: "Customer questions:\n" <> Enum.join(questions, "\n")

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
