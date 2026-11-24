defmodule Dirmoon.Hosting.Demo do
  @moduledoc """
  Demo hosting for dev without a Netlify token: answers a deterministic demo
  site id from the site name and an `.example` URL from the site id, and
  sends nothing anywhere.
  """

  @behaviour Dirmoon.Hosting

  alias Dirmoon.Hosting

  @max_name_length 63
  @site_id_prefix "demo-site-"

  @impl Hosting
  def create_site(%{site_name: site_name}) do
    {:ok, %{site_id: @site_id_prefix <> Hosting.site_name(site_name, @max_name_length)}}
  end

  @impl Hosting
  def deploy(%{site_id: site_id, html: html}) when is_binary(site_id) and is_binary(html) do
    name =
      site_id
      |> String.replace_prefix(@site_id_prefix, "")
      |> Hosting.site_name(@max_name_length)

    {:ok, %{url: "https://demo-#{name}.example"}}
  end
end
