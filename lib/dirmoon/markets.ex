defmodule Dirmoon.Markets do
  @moduledoc """
  Markets: the countries and languages a Research Run can target, as the
  keyword API lists them (`DataForSEO.countries/0`, `DataForSEO.languages/0`,
  both free). Each list is cached in the database (`market_countries`,
  `market_languages`) and fetched again on first need once it is older than
  `config :dirmoon, :market_lists_max_age_days`. A fetch that fails or
  answers an empty list leaves the stored rows in use; with nothing stored it
  is an error the new research screen shows.
  """

  import Ecto.Query

  alias Dirmoon.DataForSEO
  alias Dirmoon.Markets.Country
  alias Dirmoon.Markets.Language
  alias Dirmoon.Repo

  @default_market %{country_code: "US", language_code: "en"}

  @doc """
  The countries a run can target, sorted by name: `{:ok, [%Country{}]}`, or
  `{:error, reason}` when none are stored and the keyword API gives none.
  """
  def countries, do: stored_or_fetched(Country)

  @doc """
  The languages a run's Phrases can be in, sorted by name:
  `{:ok, [%Language{}]}`, or `{:error, reason}` when none are stored and the
  keyword API gives none.
  """
  def languages, do: stored_or_fetched(Language)

  @doc """
  The stored country and language with the given codes, each nil when the
  code is missing or not in the stored lists. Never asks the keyword API.
  """
  def find_market(%{country_code: country_code, language_code: language_code}) do
    %{
      country: find_stored(Country, country_code: country_code),
      language: find_stored(Language, language_code: language_code)
    }
  end

  @doc """
  The market a first run starts from: the United States, in English.
  """
  def default_market, do: @default_market

  defp find_stored(_schema, [{_field, nil}]), do: nil
  defp find_stored(schema, clauses), do: Repo.get_by(schema, clauses)

  defp stored_or_fetched(schema) do
    stored = list_stored(schema)

    if fresh?(stored), do: {:ok, stored}, else: refresh(schema, stored)
  end

  defp list_stored(schema) do
    schema
    |> from(as: :entry)
    |> order_by([entry: entry], asc: entry.name)
    |> Repo.all()
  end

  defp fresh?([]), do: false

  defp fresh?(stored) do
    fresh_since = DateTime.shift(DateTime.utc_now(:second), day: -max_age_days())
    Enum.all?(stored, &DateTime.after?(&1.fetched_at, fresh_since))
  end

  defp refresh(schema, stored) do
    case fetch(schema) do
      {:ok, [_entry | _more] = entries} -> {:ok, store(schema, entries)}
      {:ok, []} -> fall_back(stored, :empty_list)
      {:error, reason} -> fall_back(stored, reason)
    end
  end

  defp fall_back([], reason), do: {:error, reason}
  defp fall_back(stored, _reason), do: {:ok, stored}

  defp fetch(Country), do: DataForSEO.countries()
  defp fetch(Language), do: DataForSEO.languages()

  defp unique_key(Country), do: :country_code
  defp unique_key(Language), do: :language_code

  defp store(schema, entries) do
    fetched_at = DateTime.utc_now(:second)
    key = unique_key(schema)

    rows =
      entries
      |> Enum.uniq_by(&Map.fetch!(&1, key))
      |> Enum.map(&Map.put(&1, :fetched_at, fetched_at))

    {:ok, stored} =
      Repo.transact(fn ->
        Repo.insert_all(schema, rows, on_conflict: {:replace_all_except, [key]}, conflict_target: [key])

        schema
        |> from(as: :entry)
        |> where([entry: entry], entry.fetched_at < ^fetched_at)
        |> Repo.delete_all()

        {:ok, list_stored(schema)}
      end)

    stored
  end

  defp max_age_days, do: Application.fetch_env!(:dirmoon, :market_lists_max_age_days)
end
