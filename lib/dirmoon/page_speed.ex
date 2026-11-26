defmodule Dirmoon.PageSpeed do
  @moduledoc """
  The seam to Google PageSpeed Insights: how fast one page loads on a phone
  and whether it passes Google's phone-usability checks. The adapter is
  chosen by `config :dirmoon, :page_speed_adapter`: `Dirmoon.PageSpeed.HTTP`
  with dirmoon's own key, else `Dirmoon.PageSpeed.NotConfigured`. There is
  no Demo Data: a made-up speed would read as a fact about the owner's site.

  `check/1` answers `{:ok, %{result: result, raw: raw}}`: `raw` is Google's
  response body and `result` dirmoon's own shape (string keys), every value
  optional, since a small site has no figures from real visitors and the
  checks Google runs change between Lighthouse versions:

    * `"performance_score"`: 0–100 (integer) or nil
    * `"largest_contentful_paint_ms"`, `"total_blocking_time_ms"` (integers)
      and `"cumulative_layout_shift"` (number): measured in Google's own
      test load, nil when missing
    * `"lighthouse_version"`: string or nil
    * `"field"`: what real Chrome visitors met, only the measures Google
      has: `"largest_contentful_paint"`, `"interaction_to_next_paint"` and
      `"cumulative_layout_shift"`, each `%{"percentile" => number,
      "category" => string | nil, "scope" => "page" | "origin"}`, the
      percentile as Google reports it (for the layout shift believed to be
      the shift × 100) and the scope saying whether the figure is the
      page's own or the whole site's
    * `"phone_checks"`: `[%{"id" => string, "passed" => boolean | nil}]`,
      one per phone-usability check present in the answer, of
      `"viewport-insight"`, `"meta-viewport"` and `"target-size"`; `nil`
      when Google reports the check as not applicable

  Errors: `:page_speed_not_configured` (no key), `:page_speed_key_rejected`
  (the key is refused or the API is not enabled for it),
  `:page_speed_quota_exceeded`, `:page_unreachable` (Google could not load
  the page) or `{:page_speed_failed, message}` for anything else.
  """

  @type request :: %{url: String.t()}
  @type answer ::
          {:ok, %{result: map(), raw: map()}}
          | {:error,
             :page_speed_not_configured
             | :page_speed_key_rejected
             | :page_speed_quota_exceeded
             | :page_unreachable
             | {:page_speed_failed, String.t()}}

  @callback check(request()) :: answer()

  @doc "Checks the page at `url` as a phone loads it."
  @spec check(request()) :: answer()
  def check(%{url: url} = request) when is_binary(url), do: adapter().check(request)

  defp adapter, do: Application.fetch_env!(:dirmoon, :page_speed_adapter)
end
