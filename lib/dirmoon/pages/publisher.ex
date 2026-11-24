defmodule Dirmoon.Pages.Publisher do
  @moduledoc """
  Step 9: deploys the run's `:publishing` page through `Dirmoon.Hosting`.

  The page is rendered as the download is (`Dirmoon.Pages.render/1`, so a
  Plausible domain in the Brief brings its script) and deployed to the
  page's hosting site. A page without one first gets a new site named
  after the Brief's slug, whose id is stored before deploying, so a retry
  after a failed deploy reuses that site. Every publish deploys again;
  nothing goes through the Ledger.
  """

  alias Dirmoon.Hosting
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Research.Run

  @site_name_prefix "dirmoon-"
  @fallback_site_name "dirmoon-strona"

  @doc """
  Publishes the run's `:publishing` page. Returns
  `{:ok, %{result: "Opublikowano: <url>", output: %{"page_id", "url"}}}`,
  `{:skip, "Brak strony do publikacji"}` when no page of the run is
  publishing, or `{:error, reason}` from the hosting.
  """
  def publish(%Run{} = run) do
    case Pages.publishing_page_for_run(run) do
      nil -> {:skip, "Brak strony do publikacji"}
      %Page{} = page -> deploy(page)
    end
  end

  defp deploy(%Page{} = page) do
    with {:ok, page_with_site} <- ensure_site(page),
         {:ok, deployed} <- Hosting.deploy(%{site_id: page_with_site.hosting_site_id, html: Pages.render(page)}),
         {:ok, published_page} <- Pages.store_published(page_with_site, deployed) do
      {:ok,
       %{
         result: "Opublikowano: #{published_page.published_url}",
         output: %{"page_id" => published_page.id, "url" => published_page.published_url}
       }}
    end
  end

  defp ensure_site(%Page{hosting_site_id: site_id} = page) when is_binary(site_id) and site_id != "", do: {:ok, page}

  defp ensure_site(%Page{} = page) do
    with {:ok, %{site_id: site_id}} <- Hosting.create_site(%{site_name: site_name(page.brief)}) do
      Pages.store_hosting_site(page, site_id)
    end
  end

  defp site_name(%Brief{slug: slug}) when is_binary(slug) and slug != "", do: @site_name_prefix <> slug
  defp site_name(%Brief{}), do: @fallback_site_name
end
