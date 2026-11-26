defmodule Dirmoon.SiteScans.Robots do
  @moduledoc """
  Reads a site's robots.txt the way a crawler obeying it for every crawler
  (`User-agent: *`) does. Pure: no I/O.

  `parse/1` answers the `Allow`/`Disallow` rules of the groups that name
  `*` and every `Sitemap:` address, wherever it stands. Rules are plain
  maps with string keys (`%{"allow" => boolean, "pattern" => path}`), so
  they read the same after a round trip through a `jsonb` column. Comments,
  blank and unknown lines are skipped; an empty `Disallow` allows
  everything and is dropped. So that a hostile file can't make every check
  slow, a rule longer than 512 bytes or with more than ten `*` is dropped,
  and a file of any size keeps at most 500 rules. A `Sitemap:` address is
  kept only when it is a web address (`Dirmoon.WebPage.WebAddress`), at
  most 50 of them. The file is read as text a jsonb column can hold
  (`Dirmoon.JsonSafe.text/1`): bytes that are not UTF-8 become U+FFFD and
  NUL characters are dropped, so a rule is always storable.

  `allowed?/2` applies the rules to a path (with its query): the longest
  matching pattern wins, `Allow` on a tie; `*` matches any characters and
  a final `$` anchors the pattern at the end. No rule matching, or no
  rules at all, means allowed. Matching never backtracks: each pattern is
  matched in time linear in the path's length.
  """

  alias Dirmoon.JsonSafe
  alias Dirmoon.WebPage.WebAddress

  @max_rules 500
  @max_pattern_bytes 512
  @max_wildcards 10
  @max_sitemaps 50
  @every_crawler "*"

  @type rule :: %{String.t() => boolean() | String.t()}

  @doc "The rules for every crawler and the sitemap addresses in `robots_txt`."
  @spec parse(String.t()) :: %{rules: [rule()], sitemaps: [String.t()]}
  def parse(robots_txt) when is_binary(robots_txt) do
    reading =
      robots_txt
      |> JsonSafe.text()
      |> String.split(["\r\n", "\n", "\r"])
      |> Enum.reduce(
        %{rules: [], rule_count: 0, sitemaps: [], sitemap_count: 0, every_crawler?: false, naming_crawlers?: false},
        &read_line/2
      )

    %{rules: Enum.reverse(reading.rules), sitemaps: Enum.reverse(reading.sitemaps)}
  end

  @doc "Whether `rules` let a crawler read `path` (the address's path and query)."
  @spec allowed?([rule()], String.t()) :: boolean()
  def allowed?(rules, path) when is_list(rules) and is_binary(path) do
    rules
    |> Enum.filter(&matches?(&1["pattern"], path))
    |> Enum.max_by(&{byte_size(&1["pattern"]), &1["allow"]}, fn -> %{"allow" => true} end)
    |> Map.fetch!("allow")
  end

  defp read_line(line, reading) do
    case line |> String.split("#", parts: 2) |> hd() |> String.split(":", parts: 2) do
      [field, value] -> field |> String.trim() |> String.downcase() |> read_field(String.trim(value), reading)
      [_not_a_field] -> reading
    end
  end

  defp read_field("user-agent", agent, %{naming_crawlers?: true} = reading),
    do: %{reading | every_crawler?: reading.every_crawler? or agent == @every_crawler}

  defp read_field("user-agent", agent, reading),
    do: %{reading | every_crawler?: agent == @every_crawler, naming_crawlers?: true}

  defp read_field(field, pattern, reading) when field in ["allow", "disallow"] do
    reading = %{reading | naming_crawlers?: false}

    if reading.every_crawler? and usable_pattern?(pattern) and reading.rule_count < @max_rules,
      do: %{
        reading
        | rules: [%{"allow" => field == "allow", "pattern" => pattern} | reading.rules],
          rule_count: reading.rule_count + 1
      },
      else: reading
  end

  defp read_field("sitemap", address, reading) do
    if reading.sitemap_count < @max_sitemaps and WebAddress.acceptable?(address),
      do: %{reading | sitemaps: [address | reading.sitemaps], sitemap_count: reading.sitemap_count + 1},
      else: reading
  end

  defp read_field(_other_field, _value, reading), do: reading

  defp usable_pattern?(pattern) do
    pattern != "" and byte_size(pattern) <= @max_pattern_bytes and
      length(:binary.matches(pattern, "*")) <= @max_wildcards
  end

  defp matches?(pattern, path) do
    {body, anchored?} =
      if String.ends_with?(pattern, "$"),
        do: {binary_part(pattern, 0, byte_size(pattern) - 1), true},
        else: {pattern, false}

    [first | rest] = String.split(body, "*")

    String.starts_with?(path, first) and match_rest(rest, after_byte(path, byte_size(first)), anchored?)
  end

  defp match_rest([], remaining, anchored?), do: not anchored? or remaining == ""
  defp match_rest([last], remaining, true), do: String.ends_with?(remaining, last)
  defp match_rest(["" | rest], remaining, anchored?), do: match_rest(rest, remaining, anchored?)

  defp match_rest([segment | rest], remaining, anchored?) do
    case :binary.match(remaining, segment) do
      {at, length} -> match_rest(rest, after_byte(remaining, at + length), anchored?)
      :nomatch -> false
    end
  end

  defp after_byte(binary, offset), do: binary_part(binary, offset, byte_size(binary) - offset)
end
