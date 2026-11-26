# Makes each of the Site Scan's five outside requests ONCE, for real, and
# prints what dirmoon's own client code read from the reply. Costs about
# 8 US cents of DataForSEO credit. Prints no key.
#
#   source .env && mix run --no-start priv/live_check.exs example.com "Business Name"
#
# The domain is required. The business name is optional (for the Google
# Business Profile lookup). Location is the United States, language English.

alias Dirmoon.DataForSEO
alias Dirmoon.PageSpeed

{domain, name} =
  case System.argv() do
    [domain, name | _rest] -> {domain, name}
    [domain] -> {domain, nil}
    [] -> raise "give a domain: mix run --no-start priv/live_check.exs example.com"
  end

{:ok, _started} = Application.ensure_all_started(:req)

market = %{location_code: 2840, language_code: "en"}

show = fn label, answer ->
  summary =
    case answer do
      {:ok, %{rows: rows, cost: cost}} -> "OK   #{length(rows)} rows, first: #{inspect(Enum.take(rows, 2))}, cost #{cost}"
      {:ok, %{count: count, cost: cost}} -> "OK   count #{count}, cost #{cost}"
      {:ok, %{profile: profile, cost: cost}} -> "OK   profile #{inspect(profile)}, cost #{cost}"
      {:ok, %{result: result}} -> "OK   #{inspect(result, limit: 40)}"
      {:error, {reason, %{message: message}}} -> "REFUSED  #{reason}: #{message}"
      {:error, reason} -> "ERROR  #{inspect(reason, limit: 20)}"
    end

  IO.puts("#{String.pad_trailing(label, 22)} #{summary}")
end

IO.puts("Live check for #{domain}\n")

show.("ranked phrases", DataForSEO.HTTP.ranked_phrases(Map.merge(market, %{domain: domain, limit: 5})))
show.("indexed pages", DataForSEO.HTTP.indexed_page_count(Map.put(market, :domain, domain)))
show.("linking sites", DataForSEO.HTTP.linking_sites(%{domains: [domain]}))

if name do
  show.("business profile", DataForSEO.HTTP.business_profile(Map.put(market, :name, name)))
else
  IO.puts("business profile       skipped (no business name given)")
end

if Application.get_env(:dirmoon, :page_speed_adapter) == PageSpeed.HTTP do
  show.("phone speed", PageSpeed.HTTP.check(%{url: "https://#{domain}/"}))
else
  IO.puts("phone speed            skipped (no PAGESPEED_API_KEY in .env)")
end
