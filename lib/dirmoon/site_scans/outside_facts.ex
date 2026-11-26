defmodule Dirmoon.SiteScans.OutsideFacts do
  @moduledoc """
  What services outside the site say about an Existing Site, added to its
  Site Scan's facts once the crawl has read the pages: the home page's
  phone speed and phone-usability checks (Google PageSpeed,
  `Dirmoon.PageSpeed`), Google's rough count of the site's indexed pages,
  the business's Google Business Profile and how many other sites link to
  the site (`Dirmoon.DataForSEO`; the last through
  `Dirmoon.SiteScans.LinkingSites`). The keys and their shapes are listed
  in `Dirmoon.SiteScans.Crawler`.

  Every request goes through the run's ledger (`Dirmoon.Research.Ledger`),
  so a paid answer the run already holds is never bought again and its
  cost is in the run's API Cost; PageSpeed is recorded at no cost. Only
  answers are recorded, never a failure, so a failure is asked again on
  the next try.

  None of these can fail the scan: a request that can't be answered is
  stored as `%{"checked" => false, "reason" => reason}`, and one that
  raises, exits or throws as not checked with the reason `"failed"`. A resumed scan
  keeps a fact stored as checked. It asks again for a speed check that
  `"failed"` (anything else that stopped the check, such as a missing key
  or the quota, would stop it again), and for an indexed count, a
  Business Profile or linking sites not checked, which costs nothing when
  the ledger already holds the answer.

  The business name comes only from the Scanned Pages' structured data
  (home page first); without one the profile is not looked up, since a
  guessed name could find no profile, or another business's.
  """

  alias Dirmoon.DataForSEO
  alias Dirmoon.JsonSafe
  alias Dirmoon.PageSpeed
  alias Dirmoon.Research.Ledger
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.LinkingSites
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.WebPage.HostName

  @phone_strategy "mobile"
  @failed "failed"
  @speed_reasons %{
    page_speed_not_configured: "not_configured",
    page_speed_key_rejected: "not_configured",
    page_speed_quota_exceeded: "quota",
    page_unreachable: "page_unreachable"
  }
  @data_for_seo_reasons %{
    data_for_seo_not_configured: "not_configured",
    not_in_demo_data: "not_in_demo_data"
  }
  @no_business_name "no_business_name"
  @unavailable "unavailable"
  @max_profile_text_bytes 300

  @doc """
  Adds the speed, indexed pages, Business Profile and linking sites facts to a scan whose
  facts hold its `"home_page"`, with its run loaded; `scanned_pages` are
  the scan's pages (stored or just read), each with its `position` and
  `facts`. Returns the updated scan.
  """
  def gather(%SiteScan{} = site_scan, scanned_pages) when is_list(scanned_pages) do
    site_scan
    |> speed()
    |> indexed_pages()
    |> business_profile(scanned_pages)
    |> linking_sites()
  end

  defp speed(%SiteScan{facts: %{"speed" => %{"checked" => true}}} = site_scan), do: site_scan

  defp speed(%SiteScan{facts: %{"speed" => %{"reason" => reason}}} = site_scan) when reason != @failed, do: site_scan

  defp speed(%SiteScan{run: run, facts: %{"home_page" => home_page}} = site_scan) do
    paid_request = %{
      service: "page_speed",
      operation: "check",
      request: %{url: home_page, strategy: @phone_strategy}
    }

    fact = unless_it_crashes(fn -> speed_fact(run, paid_request) end)
    SiteScans.put_facts(site_scan, %{"speed" => fact})
  end

  defp speed_fact(run, %{request: %{url: home_page}} = paid_request) do
    case Ledger.fetch(run, paid_request, fn -> check_speed(home_page) end) do
      {:ok, %{"result" => result}} -> Map.put(result, "checked", true)
      {:error, reason} -> not_checked(Map.get(@speed_reasons, reason, @failed))
    end
  end

  defp check_speed(url) do
    with {:ok, %{result: result, raw: raw}} <- PageSpeed.check(%{url: url}) do
      {:ok, %{"result" => result, "raw" => raw}, Decimal.new(0)}
    end
  end

  defp indexed_pages(%SiteScan{facts: %{"indexed_pages" => %{"checked" => true}}} = site_scan), do: site_scan

  defp indexed_pages(%SiteScan{run: run} = site_scan) do
    paid_request = %{
      service: "dataforseo",
      operation: "indexed_page_count",
      request: %{domain: Run.ascii_domain(run), location_code: run.location_code, language_code: run.language_code}
    }

    fact = unless_it_crashes(fn -> indexed_pages_fact(run, paid_request) end)
    SiteScans.put_facts(site_scan, %{"indexed_pages" => fact})
  end

  defp indexed_pages_fact(run, paid_request) do
    case Ledger.fetch(run, paid_request, fn -> count_indexed_pages(paid_request.request) end) do
      {:ok, %{"count" => count}} -> %{"checked" => true, "count" => count}
      {:error, reason} -> not_checked(data_for_seo_reason(reason))
    end
  end

  defp count_indexed_pages(request) do
    with {:ok, %{count: count, raw: raw, cost: cost}} <- DataForSEO.indexed_page_count(request) do
      {:ok, %{"count" => count, "raw" => raw}, cost}
    end
  end

  defp business_profile(%SiteScan{facts: %{"business_profile" => %{"checked" => true}}} = site_scan, _pages),
    do: site_scan

  defp business_profile(site_scan, scanned_pages) do
    fact =
      case business_name(scanned_pages) do
        nil -> not_checked(@no_business_name)
        name -> unless_it_crashes(fn -> look_up_profile(site_scan, name) end)
      end

    SiteScans.put_facts(site_scan, %{"business_profile" => fact})
  end

  defp business_name(scanned_pages) do
    scanned_pages
    |> Enum.sort_by(& &1.position)
    |> Enum.find_value(fn
      %{facts: %{"business_name" => name}} when is_binary(name) and name != "" -> name
      _no_name -> nil
    end)
  end

  defp look_up_profile(%SiteScan{run: run, facts: %{"home_page" => home_page}}, name) do
    paid_request = %{
      service: "dataforseo",
      operation: "business_profile",
      request: %{
        name: name,
        location_code: run.city_location_code || run.location_code,
        language_code: run.language_code
      }
    }

    case Ledger.fetch(run, paid_request, fn -> buy_business_profile(paid_request.request) end) do
      {:ok, %{"profile" => profile}} -> profile_fact(profile, %{name: name, site_host: bare_host(home_page)})
      {:ok, %{"unavailable" => _message}} -> not_checked(@unavailable)
      {:error, reason} -> not_checked(data_for_seo_reason(reason))
    end
  end

  defp buy_business_profile(request) do
    case DataForSEO.business_profile(request) do
      {:ok, %{profile: profile, raw: raw, cost: cost}} ->
        {:ok, %{"profile" => profile, "raw" => raw}, cost}

      {:error, {:business_profile_unavailable, %{message: message, raw: raw, cost: cost}}} ->
        {:ok, %{"unavailable" => message, "raw" => raw}, cost}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp linking_sites(%SiteScan{facts: %{"linking_sites" => %{"checked" => true}}} = site_scan), do: site_scan

  defp linking_sites(%SiteScan{run: run} = site_scan) do
    fact = unless_it_crashes(fn -> linking_sites_fact(run) end)
    SiteScans.put_facts(site_scan, %{"linking_sites" => fact})
  end

  defp linking_sites_fact(run) do
    domain = Run.ascii_domain(run)

    case LinkingSites.count(run, [domain]) do
      {:ok, counts} -> %{"checked" => true, "count" => Map.get(counts, domain)}
      {:error, :unavailable} -> not_checked(@unavailable)
      {:error, reason} -> not_checked(data_for_seo_reason(reason))
    end
  end

  defp profile_fact(nil, %{name: name}) do
    %{
      "checked" => true,
      "name" => name,
      "found" => false,
      "links_to_site" => false,
      "title" => nil,
      "phone" => nil,
      "address" => nil,
      "rating" => nil,
      "votes" => nil,
      "claimed" => nil
    }
  end

  defp profile_fact(%{} = profile, %{name: name, site_host: site_host}) do
    %{
      "checked" => true,
      "name" => name,
      "found" => true,
      "links_to_site" => profile_host(profile) == site_host,
      "title" => capped(profile["title"]),
      "phone" => capped(profile["phone"]),
      "address" => capped(profile["address"]),
      "rating" => profile["rating"],
      "votes" => profile["votes"],
      "claimed" => profile["claimed"]
    }
  end

  defp profile_host(%{"domain" => domain}) when is_binary(domain) and domain != "", do: bare_host("//" <> domain)
  defp profile_host(%{"url" => url}) when is_binary(url), do: bare_host(url)
  defp profile_host(_no_site), do: nil

  defp bare_host(address) do
    case URI.parse(address) do
      %URI{host: host} when is_binary(host) and host != "" ->
        HostName.bare(host)

      _no_host ->
        nil
    end
  end

  defp capped(text) when is_binary(text), do: JsonSafe.text(text, @max_profile_text_bytes)
  defp capped(_missing), do: nil

  defp data_for_seo_reason(reason), do: Map.get(@data_for_seo_reasons, reason, @failed)

  defp not_checked(reason), do: %{"checked" => false, "reason" => reason}

  defp unless_it_crashes(check) do
    check.()
  rescue
    _exception -> not_checked(@failed)
  catch
    _kind, _reason -> not_checked(@failed)
  end
end
