defmodule Dirmoon.SiteScans.Findings.Visitor do
  @moduledoc """
  Findings for the question "does the site work for a visitor?"
  (`:visitor`).

  From the home page's phone speed check (the scan's `"speed"` fact): not
  checked gives one `:speed` Finding with its `reason`. Checked:

    * `:performance_score`: Google's 0–100 score: 90 or more good, 50 or
      more a warning, else a problem (figures `score`)
    * `:largest_contentful_paint`: when the main content shows, real
      visitors' figure when Google has one, else its test load's: up to
      2.5 s good, up to 4 s a warning, else a problem (figures
      `milliseconds`, `source`)
    * `:interaction_to_next_paint`: how fast the page answers a tap, real
      visitors' figure only: up to 200 ms good, up to 500 ms a warning, else
      a problem (figures `milliseconds`, `source`)
    * `:cumulative_layout_shift`: how much the page jumps while loading,
      real visitors' figure when Google has one, else the test load's: up to
      0.1 good, up to 0.25 a warning, else a problem (figures `value`,
      `source`)
    * `:phone_usability`: one warning per failed phone-usability check
      (figures `check_id`), and one good Finding listing those passed
      (figures `check_ids`)

  `source` is `"page"` or `"origin"` (real visitors of the page, or of the
  whole site) or `"lab"` (Google's test load). A figure Google did not give
  gives no Finding.

  From the readable pages:

    * `:viewport`: pages not set up for phones (warning), else good
    * `:ways_to_act`: pages with no phone link, e-mail link, form or
      button-like link (warning), else good
  """

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.SitePages

  @question :visitor
  @checks [
    speed: [:not_checked],
    performance_score: [:problem, :warning, :good],
    largest_contentful_paint: [:problem, :warning, :good],
    interaction_to_next_paint: [:problem, :warning, :good],
    cumulative_layout_shift: [:problem, :warning, :good],
    phone_usability: [:warning, :good],
    viewport: [:warning, :good],
    ways_to_act: [:warning, :good]
  ]
  @check_levels for {check, levels} <- @checks, level <- levels, do: {check, level}
  @performance_score %{good: 90, warning: 50}
  @largest_contentful_paint_ms %{good: 2_500, warning: 4_000}
  @interaction_to_next_paint_ms %{good: 200, warning: 500}
  @cumulative_layout_shift %{good: 0.1, warning: 0.25}
  @field_layout_shift_scale 100
  @lab_source "lab"

  @doc "Every check this rule makes, with each level it can give: `[%{question:, check:, level:}]`."
  def checks, do: for({check, level} <- @check_levels, do: %{question: @question, check: check, level: level})

  @doc "The `:visitor` Findings of the site (`Dirmoon.SiteScans.Findings`)."
  def check(%{facts: facts, pages: pages}) do
    readable = SitePages.readable(pages)
    List.flatten([speed(facts["speed"]), viewport(readable), ways_to_act(readable)])
  end

  defp speed(%{"checked" => true} = speed) do
    field = if is_map(speed["field"]), do: speed["field"], else: %{}

    [
      performance_score(speed["performance_score"]),
      largest_contentful_paint(field["largest_contentful_paint"], speed["largest_contentful_paint_ms"]),
      interaction_to_next_paint(field["interaction_to_next_paint"]),
      cumulative_layout_shift(field["cumulative_layout_shift"], speed["cumulative_layout_shift"]),
      phone_usability(speed["phone_checks"])
    ]
  end

  defp speed(%{"checked" => false} = speed), do: finding(:speed, :not_checked, %{figures: %{reason: speed["reason"]}})
  defp speed(_missing), do: []

  defp performance_score(score) when is_number(score) do
    level =
      cond do
        score >= @performance_score.good -> :good
        score >= @performance_score.warning -> :warning
        true -> :problem
      end

    finding(:performance_score, level, %{figures: %{score: score}})
  end

  defp performance_score(_missing), do: []

  defp largest_contentful_paint(%{"percentile" => milliseconds, "scope" => scope}, _lab) when is_number(milliseconds),
    do: timing(:largest_contentful_paint, %{milliseconds: milliseconds, source: scope}, @largest_contentful_paint_ms)

  defp largest_contentful_paint(_no_field, milliseconds) when is_number(milliseconds) do
    figures = %{milliseconds: milliseconds, source: @lab_source}
    timing(:largest_contentful_paint, figures, @largest_contentful_paint_ms)
  end

  defp largest_contentful_paint(_no_field, _no_lab), do: []

  defp interaction_to_next_paint(%{"percentile" => milliseconds, "scope" => scope}) when is_number(milliseconds),
    do: timing(:interaction_to_next_paint, %{milliseconds: milliseconds, source: scope}, @interaction_to_next_paint_ms)

  defp interaction_to_next_paint(_no_field), do: []

  defp cumulative_layout_shift(%{"percentile" => percentile, "scope" => scope}, _lab) when is_number(percentile),
    do: layout_shift(%{value: percentile / @field_layout_shift_scale, source: scope})

  defp cumulative_layout_shift(_no_field, value) when is_number(value),
    do: layout_shift(%{value: value, source: @lab_source})

  defp cumulative_layout_shift(_no_field, _no_lab), do: []

  defp layout_shift(%{value: value} = figures),
    do: finding(:cumulative_layout_shift, level(value, @cumulative_layout_shift), %{figures: figures})

  defp timing(check, %{milliseconds: milliseconds} = figures, thresholds),
    do: finding(check, level(milliseconds, thresholds), %{figures: figures})

  defp level(value, %{good: good, warning: warning}) do
    cond do
      value <= good -> :good
      value <= warning -> :warning
      true -> :problem
    end
  end

  defp phone_usability(phone_checks) when is_list(phone_checks) do
    failed =
      for %{"passed" => false, "id" => id} <- phone_checks,
          do: finding(:phone_usability, :warning, %{figures: %{check_id: id}})

    passed =
      case for(%{"passed" => true, "id" => id} <- phone_checks, do: id) do
        [] -> []
        check_ids -> finding(:phone_usability, :good, %{figures: %{check_ids: check_ids}})
      end

    [failed, passed]
  end

  defp phone_usability(_not_a_list), do: []

  defp viewport([]), do: []

  defp viewport(readable) do
    case Enum.filter(readable, &(&1.facts["viewport"] == false)) do
      [] -> finding(:viewport, :good)
      unset -> finding(:viewport, :warning, %{pages: Enum.map(unset, & &1.url)})
    end
  end

  defp ways_to_act([]), do: []

  defp ways_to_act(readable) do
    case Enum.filter(readable, &no_way_to_act?/1) do
      [] -> finding(:ways_to_act, :good)
      dead_ends -> finding(:ways_to_act, :warning, %{pages: Enum.map(dead_ends, & &1.url)})
    end
  end

  defp no_way_to_act?(%{facts: %{"ways_to_act" => %{} = ways_to_act}}),
    do: ways_to_act |> Map.values() |> Enum.all?(&(&1 == 0))

  defp no_way_to_act?(_page), do: false

  defp finding(check, level, attributes \\ %{}) when {check, level} in @check_levels,
    do: Finding.new(Map.merge(attributes, %{question: @question, check: check, level: level}))
end
