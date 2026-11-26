defmodule Dirmoon.WebPage.WebAddress do
  @moduledoc """
  The one rule for which addresses dirmoon reads and keeps: an absolute
  `http` or `https` address with a host, at most 2,048 bytes long. The
  sitemap, the links of a page, robots.txt's sitemap lines and every
  address the web page seam follows go through it, so no stored address is
  longer. An international host counts by its ASCII form
  (`Dirmoon.WebPage.HostName`): `with_ascii_host/1` gives the address as it
  is requested. Pure: no I/O, and host names are not resolved
  (`Dirmoon.WebPage.PublicUrl` adds the network rule).
  """

  alias Dirmoon.WebPage.HostName

  @max_bytes 2_048
  @web_schemes ["http", "https"]

  @doc "Whether `address` is an http(s) address with a host, at most #{@max_bytes} bytes long."
  @spec acceptable?(String.t()) :: boolean()
  def acceptable?(address) when is_binary(address) do
    with false <- too_long?(address),
         {:ok, ascii_address} <- with_ascii_host(address),
         {:ok, %URI{scheme: scheme, host: host}} <- URI.new(ascii_address) do
      scheme in @web_schemes and is_binary(host) and host != ""
    else
      _not_acceptable -> false
    end
  end

  @doc "Whether `address` is longer than any address dirmoon reads or keeps."
  @spec too_long?(String.t()) :: boolean()
  def too_long?(address) when is_binary(address), do: byte_size(address) > @max_bytes

  @doc """
  `address` with its host in ASCII form (`Dirmoon.WebPage.HostName.to_ascii/1`):
  `{:ok, address}`, unchanged when the host is already ASCII or there is
  none, or `:error` when the host can't be encoded.
  """
  @spec with_ascii_host(String.t()) :: {:ok, String.t()} | :error
  def with_ascii_host(address) when is_binary(address) do
    case URI.parse(address) do
      %URI{host: host} = uri when is_binary(host) -> address_at_ascii_host(%{address: address, uri: uri})
      %URI{host: nil} -> {:ok, address}
    end
  end

  defp address_at_ascii_host(%{address: address, uri: %URI{host: host} = uri}) do
    case HostName.to_ascii(host) do
      {:ok, ^host} -> {:ok, address}
      {:ok, ascii_host} -> {:ok, URI.to_string(%{uri | host: ascii_host})}
      :error -> :error
    end
  end
end
