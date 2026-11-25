defmodule Dirmoon.WebPage.PublicUrl do
  @moduledoc """
  Whether an address may be read from the server: only `http` and `https`
  with a host, never `localhost` nor an IP literal in a loopback, private,
  link-local, shared or unspecified range (a basic guard against making the
  server read its own network). Host names are not resolved.
  """

  import Bitwise

  @web_schemes ["http", "https"]
  @local_names ["localhost"]
  @refused_ipv4_ranges [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 168, 0, 0}, 16}
  ]
  @refused_ipv6_ranges [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10}
  ]
  @ipv4_mapped_prefix {0, 0, 0, 0, 0, 0xFFFF}

  @doc """
  Returns `:ok` for an address the server may read, else
  `{:error, reason}` with a readable reason.
  """
  def check(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in @web_schemes and is_binary(host) and host != "" ->
        host |> String.downcase() |> String.trim_trailing(".") |> check_host()

      _other ->
        {:error, "the address is not an http or https page"}
    end
  end

  defp check_host(host) do
    cond do
      local_name?(host) -> {:error, "a local address"}
      refused_ip?(:inet.parse_address(String.to_charlist(host))) -> {:error, "an address in a private network"}
      true -> :ok
    end
  end

  defp local_name?(host), do: host in @local_names or String.ends_with?(host, ".localhost")

  defp refused_ip?({:ok, {a, b, c, d}}), do: in_ranges?({a, b, c, d}, %{ranges: @refused_ipv4_ranges, bits: 8})

  defp refused_ip?({:ok, {p1, p2, p3, p4, p5, p6, high, low}}) do
    if {p1, p2, p3, p4, p5, p6} == @ipv4_mapped_prefix do
      refused_ip?({:ok, {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}})
    else
      in_ranges?({p1, p2, p3, p4, p5, p6, high, low}, %{ranges: @refused_ipv6_ranges, bits: 16})
    end
  end

  defp refused_ip?({:error, _not_an_ip}), do: false

  defp in_ranges?(address, %{ranges: ranges, bits: bits}) do
    number = to_integer(address, bits)
    width = tuple_size(address) * bits

    Enum.any?(ranges, fn {network, prefix_length} ->
      shift = width - prefix_length
      number >>> shift == to_integer(network, bits) >>> shift
    end)
  end

  defp to_integer(address, bits) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, number -> (number <<< bits) + part end)
  end
end
