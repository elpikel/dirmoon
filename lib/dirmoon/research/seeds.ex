defmodule Dirmoon.Research.Seeds do
  @moduledoc """
  Step 1: the LLM guesses 10–20 Seeds and the questions customers ask from a
  Research Run's description. Seeds live only in the Step output; Expansion
  decides which of them are real Phrases. Seeds and questions belong to the
  run's market, so the LLM writes them in the market language.
  """

  alias Dirmoon.Format
  alias Dirmoon.LLM
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @minimum_seeds 10
  @maximum_seeds 20
  @too_few_seeds_error "The model returned too few seed phrases"
  @seed_forms %{one: "seed phrase", other: "seed phrases"}
  @question_forms %{one: "question", other: "questions"}

  @system """
  You are an SEO specialist. From a business description you guess how its customers \
  search Google for its services. You write in the language of the business's market. \
  You answer only in JSON that matches the schema.\
  """

  @schema %{
    type: "object",
    properties: %{
      seeds: %{type: "array", items: %{type: "string"}, minItems: @minimum_seeds, maxItems: @maximum_seeds},
      questions: %{type: "array", items: %{type: "string"}}
    },
    required: ["seeds", "questions"]
  }

  @doc """
  Asks the LLM for the run's Seeds and customer questions through the run's
  ledger, so the same prompt is never paid for twice. The answer is cleaned
  before it is recorded, so a rejected answer is never stored and a retry
  asks the LLM again.

  Returns `{:ok, %{result: "18 seed phrases, 12 questions", output: %{"seeds" => [...], "questions" => [...]}}}`,
  `{:error, "The model returned too few seed phrases"}` when fewer than 10 Seeds
  are left after cleaning, or the LLM's `{:error, reason}`.
  """
  def generate(%Run{} = run) do
    request = request(run)

    with {:ok, output} <-
           Ledger.fetch(run, %{service: "llm", operation: "seeds", request: request}, fn -> cleaned_seeds(request) end) do
      {:ok, %{result: result_line(output), output: output}}
    end
  end

  defp cleaned_seeds(request) do
    with {:ok, answer, cost} <- LLM.structured(request),
         {:ok, output} <- clean_answer(answer),
         do: {:ok, output, cost}
  end

  defp request(run) do
    %{
      task: :seeds,
      system: @system,
      prompt: prompt(run),
      schema: @schema,
      input: %{description: run.description, city: run.city, priority_services: run.priority_services}
    }
  end

  defp prompt(run) do
    [
      "Business description:\n#{run.description}",
      mode_line(run),
      "Country: #{run.country_code}. Market language: #{Run.language_name(run)}.",
      "Give #{@minimum_seeds} to #{@maximum_seeds} seed phrases: short, in lower case, " <>
        "the way customers type them into Google, written in #{Run.language_name(run)}.",
      priority_services_line(run.priority_services),
      city_line(run.city),
      "Also list the questions this business's customers ask, written in #{Run.language_name(run)}."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}), do: "Mode: existing site, domain: #{domain}."
  defp mode_line(%Run{mode: :new_idea}), do: "Mode: new idea, the business has no site yet."

  defp priority_services_line([]), do: nil

  defp priority_services_line(priority_services) do
    "First give seed phrases about these services: #{Enum.join(priority_services, ", ")}. " <>
      "Only then the other phrases."
  end

  defp city_line(city) when city in [nil, ""], do: nil

  defp city_line(city) do
    "The business works in the city of #{city}. Add variants with the city's name (e.g. “… #{String.downcase(city)}”)."
  end

  defp clean_answer(answer) do
    seeds = answer |> strings_at("seeds") |> Enum.map(&String.downcase/1) |> Enum.uniq()
    questions = answer |> strings_at("questions") |> Enum.uniq()

    if length(seeds) < @minimum_seeds do
      {:error, @too_few_seeds_error}
    else
      {:ok, %{"seeds" => Enum.take(seeds, @maximum_seeds), "questions" => questions}}
    end
  end

  defp strings_at(answer, key) do
    answer
    |> Map.get(key)
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp result_line(%{"seeds" => seeds, "questions" => questions}) do
    "#{counted(length(seeds), @seed_forms)}, #{counted(length(questions), @question_forms)}"
  end

  defp counted(count, forms), do: "#{count} #{Format.plural(count, forms)}"
end
