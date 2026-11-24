defmodule Dirmoon.Research.Seeds do
  @moduledoc """
  Step 1: the LLM guesses 10–20 Seeds and the questions customers ask from a
  Research Run's description. Seeds live only in the Step output; Expansion
  decides which of them are real Phrases.
  """

  alias Dirmoon.LLM
  alias Dirmoon.Polish
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @minimum_seeds 10
  @maximum_seeds 20
  @too_few_seeds_error "Model zwrócił za mało fraz startowych"
  @seed_forms %{one: "fraza startowa", few: "frazy startowe", many: "fraz startowych"}
  @question_forms %{one: "pytanie", few: "pytania", many: "pytań"}
  @language_names %{"pl" => "polskim"}

  @system """
  Jesteś specjalistą SEO. Na podstawie opisu firmy zgadujesz, jak jej klienci \
  szukają jej usług w Google. Odpowiadasz wyłącznie w formacie JSON zgodnym ze schematem.\
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

  Returns `{:ok, %{result: "18 fraz startowych, 12 pytań", output: %{"seeds" => [...], "questions" => [...]}}}`,
  `{:error, "Model zwrócił za mało fraz startowych"}` when fewer than 10 Seeds
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
      "Opis firmy:\n#{run.description}",
      mode_line(run),
      "Kraj: #{run.country_code}.",
      "Podaj od #{@minimum_seeds} do #{@maximum_seeds} fraz startowych: krótkich, pisanych małymi literami, " <>
        "takich, jakie klienci wpisują w Google, w języku #{language_name(run.language_code)}.",
      priority_services_line(run.priority_services),
      city_line(run.city),
      "Podaj też listę pytań, które zadają klienci tej firmy."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp mode_line(%Run{mode: :existing_site, domain: domain}), do: "Tryb: istniejąca strona, domena: #{domain}."
  defp mode_line(%Run{mode: :new_idea}), do: "Tryb: nowy pomysł, firma nie ma jeszcze strony."

  defp language_name(language_code), do: Map.get(@language_names, language_code, language_code)

  defp priority_services_line([]), do: nil

  defp priority_services_line(priority_services) do
    "Najpierw podaj frazy startowe dotyczące tych usług: #{Enum.join(priority_services, ", ")}. " <>
      "Dopiero potem pozostałe frazy."
  end

  defp city_line(city) when city in [nil, ""], do: nil

  defp city_line(city) do
    "Firma działa w mieście #{city}. Dodaj warianty z nazwą miasta (np. „… #{String.downcase(city)}”)."
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

  defp counted(count, forms), do: "#{count} #{Polish.plural(count, forms)}"
end
