defmodule Dirmoon.Phrases.Volumes do
  @moduledoc """
  Step 3: Volume, CPC and Trend for the run's kept Phrases in the country and,
  when the run has a city that resolves to a keyword API location, in the
  city. Only Phrases without a fresh Volume for a location are requested
  (fresh Volumes are shared across runs, ADR-0002), in batches of at most
  `Dirmoon.DataForSEO.max_phrases/0`, each through the run's ledger. The city
  is looked up once and its location code kept on the run; a city that
  doesn't resolve is recorded too, so it is never looked up again.
  """

  alias Dirmoon.DataForSEO
  alias Dirmoon.Phrases
  alias Dirmoon.Phrases.LedgerRows
  alias Dirmoon.Research
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run

  @trend_suffix "trend 12 miesięcy"
  @city_not_found_result "Brak danych dla miasta, używam wolumenu krajowego"

  @doc """
  Fetches the missing Volumes of the run's kept Phrases for the country and
  the city.

  Returns `{:ok, %{result: "Polska i Gdańsk, trend 12 miesięcy", output: output}}`
  with `output` `%{"country" => coverage, "city" => coverage | nil, "city_location_code" => integer | nil}`,
  a coverage being `%{"location_code", "requested", "reused"}`, or the keyword
  API's `{:error, reason}` (batches fetched before it stay in the ledger and
  their Volumes stay stored).
  """
  def fetch(%Run{} = run) do
    with {:ok, city_location} <- city_location(run),
         {:ok, country_coverage} <- cover(run, run.location_code),
         {:ok, city_coverage} <- cover_city(run, city_location) do
      {:ok,
       %{
         result: result_line(run, city_location),
         output: %{
           "country" => country_coverage,
           "city" => city_coverage,
           "city_location_code" => if(is_integer(city_location), do: city_location)
         }
       }}
    end
  end

  defp city_location(%Run{city: city}) when city in [nil, ""], do: {:ok, nil}
  defp city_location(%Run{city_location_code: code}) when is_integer(code), do: {:ok, code}

  defp city_location(run) do
    request = %{city: run.city, country_code: run.country_code}

    with {:ok, %{"location_code" => location_code}} <-
           Ledger.fetch(run, %{service: "dataforseo", operation: "find_location", request: request}, fn ->
             find_location(request)
           end) do
      store_city_location(run, location_code)
    end
  end

  defp find_location(request) do
    case DataForSEO.find_location(request) do
      {:ok, %{location_code: location_code, name: name, cost: cost}} ->
        {:ok, %{"location_code" => location_code, "name" => name}, cost}

      {:error, :not_found} ->
        {:ok, %{"location_code" => nil, "name" => nil}, Decimal.new(0)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_city_location(_run, nil), do: {:ok, :not_found}

  defp store_city_location(run, location_code) do
    with {:ok, _run} <- Research.put_city_location(run, location_code), do: {:ok, location_code}
  end

  defp cover_city(run, city_location) when is_integer(city_location), do: cover(run, city_location)
  defp cover_city(_run, _no_city_location), do: {:ok, nil}

  defp cover(run, location_code) do
    phrases = Phrases.phrases_needing_volume(run, location_code)
    batches = Enum.chunk_every(phrases, DataForSEO.max_phrases())

    with :ok <- fetch_batches(run, location_code, batches) do
      requested = length(phrases)

      {:ok,
       %{
         "location_code" => location_code,
         "requested" => requested,
         "reused" => Phrases.count_kept_for_run(run) - requested
       }}
    end
  end

  defp fetch_batches(run, location_code, batches) do
    Enum.reduce_while(batches, :ok, fn batch, :ok ->
      case fetch_batch(run, location_code, batch) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_batch(run, location_code, phrases) do
    request = %{phrases: Enum.map(phrases, & &1.phrase), location_code: location_code, language_code: run.language_code}

    with {:ok, fetched} <-
           LedgerRows.fetch(run, %{operation: "search_volumes", request: request}, &DataForSEO.search_volumes/1),
         {:ok, _count} <- Phrases.store_volumes(location_code, Map.put(fetched, :phrases, phrases)) do
      :ok
    end
  end

  defp result_line(_run, :not_found), do: @city_not_found_result
  defp result_line(run, nil), do: "#{country_name(run)}, #{@trend_suffix}"
  defp result_line(run, _city_location), do: "#{country_name(run)} i #{run.city}, #{@trend_suffix}"

  defp country_name(%Run{country_code: country_code}) do
    Run.locations()
    |> Enum.find(%{country_name: country_code}, &(&1.country_code == country_code))
    |> Map.fetch!(:country_name)
  end
end
