defmodule Dirmoon.DataForSEO.Demo do
  @moduledoc """
  Demo Data for DataForSEO: deterministic, visibly synthetic answers built
  from the request, at no cost. Used in dev while no credentials are set.

  Volumes, CPC and trends come from `:erlang.phash2/2` of the phrase and
  location, so the same phrase always gets the same numbers. Any city
  resolves to one demo location whose volumes are a tenth of the country's.
  SERP results sit on `.example` domains.
  """

  @behaviour Dirmoon.DataForSEO

  alias Dirmoon.DataForSEO

  @marker Dirmoon.demo_marker()
  @ideas_per_seed 15
  @trend_months 12
  @city_location_code 9_990_001
  @city_volume_divisor 10
  @minimum_volume 10
  @volume_range 5_000
  @cpc_cents_range 999
  @trend_floor_percent 80
  @trend_spread_percent 41
  @currency "USD"
  @raw %{"demo" => true}
  @domains ~w(
    demo-blog-1.example
    demo-forum.example
    demo-business-1.example
    demo-directory.example
    demo-portal.example
    demo-business-2.example
    demo-blog-2.example
    demo-comparison.example
    demo-business-3.example
    demo-guide.example
  )

  @impl DataForSEO
  def phrase_ideas(%{seeds: seeds, location_code: location_code}) do
    with :ok <- DataForSEO.ensure_within_limit(seeds, DataForSEO.max_seeds()) do
      seeds
      |> Enum.flat_map(&[&1 | Enum.map(1..@ideas_per_seed, fn number -> "#{&1} demo #{number}" end)])
      |> Enum.uniq()
      |> Enum.map(&phrase_row(&1, location_code))
      |> answer()
    end
  end

  @impl DataForSEO
  def search_volumes(%{phrases: phrases, location_code: location_code}) do
    with :ok <- DataForSEO.ensure_within_limit(phrases, DataForSEO.max_phrases()) do
      phrases
      |> Enum.map(&phrase_row(&1, location_code))
      |> answer()
    end
  end

  @impl DataForSEO
  def serp_top10(%{phrase: phrase}) do
    rotation = :erlang.phash2(phrase, Enum.count(@domains))

    {head, tail} = Enum.split(@domains, rotation)

    (tail ++ head)
    |> Enum.with_index(1)
    |> Enum.map(fn {domain, position} ->
      %{
        position: position,
        url: "https://#{domain}/demo-#{:erlang.phash2({phrase, domain})}",
        domain: domain,
        title: "#{@marker} #{phrase} – #{domain}"
      }
    end)
    |> answer()
  end

  @impl DataForSEO
  def find_location(%{city: city}) do
    {:ok, %{location_code: @city_location_code, name: "#{@marker} #{city}", raw: @raw, cost: Decimal.new(0)}}
  end

  defp answer(rows), do: {:ok, %{rows: rows, raw: @raw, cost: Decimal.new(0)}}

  defp phrase_row(phrase, location_code) do
    volume = volume(phrase, location_code)

    %{
      phrase: phrase,
      search_volume: volume,
      cpc: Decimal.new(1, 1 + :erlang.phash2({phrase, :cpc}, @cpc_cents_range), -2),
      currency: @currency,
      trend: trend(%{phrase: phrase, location_code: location_code, volume: volume})
    }
  end

  defp volume(phrase, @city_location_code), do: phrase |> volume(:country) |> div(@city_volume_divisor)

  defp volume(phrase, _location_code), do: @minimum_volume + :erlang.phash2({phrase, :volume}, @volume_range)

  defp trend(%{phrase: phrase, location_code: location_code, volume: volume}) do
    today = Date.utc_today()

    Enum.map(1..@trend_months, fn months_back ->
      %{year: year, month: month} = Date.shift(today, month: -months_back)
      percent = @trend_floor_percent + :erlang.phash2({phrase, location_code, year, month}, @trend_spread_percent)

      %{year: year, month: month, search_volume: div(volume * percent, 100)}
    end)
  end
end
