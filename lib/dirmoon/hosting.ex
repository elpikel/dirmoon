defmodule Dirmoon.Hosting do
  @moduledoc """
  The seam to the static hosting a Page is published to (Netlify).
  The adapter is chosen by `config :dirmoon, :hosting_adapter`.

  `create_site/1` creates a site (its name derived from `site_name`) and
  `deploy/1` puts one self-contained HTML document live as an existing
  site's `index.html`. They are separate calls so the caller can store a
  new site's id before deploying, and a failed deploy never leaves a site
  nobody knows about. Every deploy is sent again: hosting is not a paid
  per-request API, so it never goes through the Ledger.
  """

  @type site_request :: %{site_name: String.t()}
  @type site :: %{site_id: String.t()}
  @type deploy_request :: %{site_id: String.t(), html: binary()}
  @type deployed :: %{url: String.t()}

  @callback create_site(site_request()) :: {:ok, site()} | {:error, term()}
  @callback deploy(deploy_request()) :: {:ok, deployed()} | {:error, term()}

  @doc "Creates a new site named after `site_name` and answers its id."
  @spec create_site(site_request()) :: {:ok, site()} | {:error, term()}
  def create_site(request), do: adapter().create_site(request)

  @doc "Deploys the HTML as the site's `index.html` and answers its live URL."
  @spec deploy(deploy_request()) :: {:ok, deployed()} | {:error, term()}
  def deploy(request), do: adapter().deploy(request)

  @doc """
  A site name the host accepts, from any text: lowercase `a-z`, `0-9` and
  single hyphens, at most `max_length` characters, never empty.
  """
  def site_name(text, max_length) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.slice(0, max_length)
    |> String.trim("-")
    |> case do
      "" -> "dirmoon"
      name -> name
    end
  end

  defp adapter, do: Application.fetch_env!(:dirmoon, :hosting_adapter)
end
