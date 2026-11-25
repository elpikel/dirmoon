defmodule Dirmoon.WebPage do
  @moduledoc """
  The seam to the public web: reads one web page and returns its visible
  text, for a Price Check to look for prices in. The adapter is chosen by
  `config :dirmoon, :web_page_adapter`; it needs no credentials, so the real
  adapter (`Dirmoon.WebPage.HTTP`) is the default outside test.

  An answer carries the page's visible `text` and the `url` actually read
  (after redirects).
  """

  @type page :: %{text: String.t(), url: String.t()}

  @callback fetch_text(String.t()) :: {:ok, page()} | {:error, String.t()}

  @doc "Reads the page at `url` through the configured adapter."
  @spec fetch_text(String.t()) :: {:ok, page()} | {:error, String.t()}
  def fetch_text(url) when is_binary(url), do: adapter().fetch_text(url)

  defp adapter, do: Application.fetch_env!(:dirmoon, :web_page_adapter)
end
