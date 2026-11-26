defmodule Dirmoon.DataForSEO.NotConfigured do
  @moduledoc """
  The DataForSEO adapter used when no credentials are configured: every
  request fails with `:data_for_seo_not_configured`.
  """

  @behaviour Dirmoon.DataForSEO

  @impl Dirmoon.DataForSEO
  def phrase_ideas(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def search_volumes(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def serp_top10(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def ranked_phrases(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def indexed_page_count(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def business_profile(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def linking_sites(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def find_location(_request), do: not_configured()

  @impl Dirmoon.DataForSEO
  def countries, do: not_configured()

  @impl Dirmoon.DataForSEO
  def languages, do: not_configured()

  defp not_configured, do: {:error, :data_for_seo_not_configured}
end
