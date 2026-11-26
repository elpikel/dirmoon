defmodule DirmoonWeb.PageComparison do
  @moduledoc """
  The Niche's "your page against theirs" table on the results screen: the
  site's page for the Niche (its first matched Scanned Page, by read order)
  beside each Competitor Page a Price Check has read, compared on the
  Page Facts both keep (`Dirmoon.WebPage.PageFacts.comparison/1`) and on
  how many other sites link to each site.

  `build/1` decides whether there is a table and shapes its rows; `table/1`
  draws it. There is a table only for an Existing Site run whose Price
  Check has read at least one page. The site's row says in a few words why
  there is nothing to compare yet (no scan, still reading, unreadable, not
  matched yet, no page for the Niche). Whether the site's page states a
  price is never known: prices are looked for on competitors' pages only.
  A figure that is unknown is shown as "—". The table scrolls inside its
  own box on a narrow screen, never the page.
  """
  use DirmoonWeb, :html

  alias Dirmoon.Format
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.WebPage.HostName
  alias Dirmoon.WebPage.PageFacts
  alias Dirmoon.WebPage.WebAddress

  @missing "—"
  @contact_kinds [{"phone_links", "phone"}, {"email_links", "e-mail"}, {"forms", "form"}]

  @site_states %{
    no_scan: "I haven't read your site, so I have no page of yours to compare.",
    scanning: "I'm still reading your site.",
    failed: "I couldn't read your site, so I have no page of yours to compare.",
    not_matched: "I haven't matched your pages to the topics yet.",
    no_page:
      "You have no page for this topic yet. Choose this topic below and the brief I write is the plan and the text for one."
  }

  @legend [
    {"Words", "How much text a visitor can read on the page."},
    {"Headings", "The page's main heading, and the smaller ones that split it into sections."},
    {"Structured data", "Labels in the page code that tell Google your name, address and prices."},
    {"States a price",
     "Whether I found a price on the page when I checked competitor prices. I don't look for prices on your own page."},
    {"Ways to contact", "Phone and e-mail links a visitor can tap, and forms they can fill in."},
    {"Sites linking to it",
     "How many other sites link to the whole site. It comes from a third-party index of links, so it is approximate."}
  ]

  @doc """
  The comparison for the selected Niche, or nil when there is none to
  show: `run`, its Niche's `price_check` (nil when none) and the site's
  side (`Dirmoon.SiteScans.niche_comparison/2`, nil when the run has no
  scan).
  """
  def build(%{run: %Run{mode: :existing_site}, price_check: %PriceCheck{competitor_pages: pages}, site: site}) do
    case Enum.reject(pages, &(&1.outcome == :waiting)) do
      [] -> nil
      read_pages -> %{site: site_row(site), competitors: Enum.map(read_pages, &competitor_row/1)}
    end
  end

  def build(%{run: %Run{}}), do: nil

  attr :comparison, :map, required: true

  def table(assigns) do
    assigns = assign(assigns, legend: @legend)

    ~H"""
    <section id="page-comparison" class="flex flex-col gap-2.5">
      <h3 class="m-0 font-mono text-[11px] font-normal uppercase tracking-[0.08em] text-on-app-muted">
        Your page against theirs
      </h3>
      <div class="overflow-x-auto rounded-tile border border-app-line-strong bg-app-raised">
        <table class="w-full border-collapse text-sm max-[859px]:min-w-[640px]">
          <thead class="text-left font-mono text-[10px] uppercase tracking-[0.08em] text-on-app-muted">
            <tr>
              <th scope="col" class="border-b border-app-line-strong px-4 py-3 font-medium">Page</th>
              <th
                scope="col"
                class="border-b border-app-line-strong px-2.5 py-3 text-right font-medium"
              >
                Words
              </th>
              <th scope="col" class="border-b border-app-line-strong px-2.5 py-3 font-medium">
                Headings
              </th>
              <th scope="col" class="border-b border-app-line-strong px-2.5 py-3 font-medium">
                Structured data
              </th>
              <th scope="col" class="border-b border-app-line-strong px-2.5 py-3 font-medium">
                States a price
              </th>
              <th scope="col" class="border-b border-app-line-strong px-2.5 py-3 font-medium">
                Ways to contact
              </th>
              <th scope="col" class="border-b border-app-line-strong px-4 py-3 text-right font-medium">
                Sites linking to it
              </th>
            </tr>
          </thead>
          <tbody>
            <tr id="page-comparison-site" data-state={@comparison.site.state}>
              <th scope="row" class="px-4 py-3 text-left align-top font-medium">
                <span class="flex min-w-0 flex-col gap-0.5">
                  <span>Your page</span>
                  <.page_address :if={@comparison.site.address} address={@comparison.site.address} />
                  <span :if={@comparison.site.note} data-part="note" class="text-xs text-on-app-muted">
                    {@comparison.site.note}
                  </span>
                </span>
              </th>
              <td
                :if={@comparison.site.message}
                colspan="5"
                data-part="message"
                class="px-2.5 py-3 align-top text-on-app-2"
              >
                {@comparison.site.message}
              </td>
              <.figure_cells :if={is_nil(@comparison.site.message)} row={@comparison.site} />
              <td
                data-part="linking-sites"
                class="px-4 py-3 text-right align-top font-mono whitespace-nowrap"
              >
                {@comparison.site.linking_sites}
              </td>
            </tr>
            <tr :for={row <- @comparison.competitors} id={row.id} data-outcome={row.outcome}>
              <th
                scope="row"
                class="border-t border-app-line-strong px-4 py-3 text-left align-top font-medium"
              >
                <span class="flex min-w-0 flex-col gap-0.5">
                  <.link
                    :if={row.href}
                    href={row.href}
                    target="_blank"
                    rel="noopener noreferrer nofollow"
                    data-part="domain"
                    class="break-all text-on-app underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:decoration-accent"
                  >
                    {row.domain}
                  </.link>
                  <span :if={is_nil(row.href)} data-part="domain" class="break-all">{row.domain}</span>
                  <span :if={row.note} data-part="note" class="text-xs font-normal text-on-app-muted">
                    {row.note}
                  </span>
                </span>
              </th>
              <.figure_cells row={row} class="border-t border-app-line-strong" />
              <td
                data-part="linking-sites"
                class="border-t border-app-line-strong px-4 py-3 text-right align-top font-mono whitespace-nowrap"
              >
                {row.linking_sites}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <dl
        id="page-comparison-legend"
        class="m-0 grid grid-cols-[repeat(auto-fit,minmax(min(220px,100%),1fr))] gap-x-5 gap-y-2 text-xs leading-normal"
      >
        <div :for={{term, meaning} <- @legend} class="flex flex-col gap-0.5">
          <dt class="font-medium text-on-app-2">{term}</dt>
          <dd class="m-0 text-on-app-muted">{meaning}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :class, :string, default: nil

  defp figure_cells(assigns) do
    ~H"""
    <td data-part="words" class={["px-2.5 py-3 text-right align-top font-mono", @class]}>
      {@row.words}
    </td>
    <td data-part="headings" class={["px-2.5 py-3 align-top text-on-app-2", @class]}>
      {@row.headings}
    </td>
    <td data-part="structured-data" class={["px-2.5 py-3 align-top", @class]}>
      <span class="flex flex-col gap-0.5" title={@row.types}>
        <span>{@row.structured_data}</span>
        <span :if={@row.types} data-part="types" class="text-xs break-words text-on-app-muted">
          {@row.types}
        </span>
      </span>
    </td>
    <td data-part="states-price" class={["px-2.5 py-3 align-top", @class]}>{@row.states_price}</td>
    <td data-part="contact" class={["px-2.5 py-3 align-top text-on-app-2", @class]}>
      {@row.contact}
    </td>
    """
  end

  attr :address, :string, required: true

  defp page_address(assigns) do
    ~H"""
    <.link
      :if={WebAddress.acceptable?(@address)}
      href={@address}
      target="_blank"
      rel="noopener noreferrer nofollow"
      data-part="address"
      class="text-xs font-normal break-all text-on-app-2 underline decoration-app-line-strong underline-offset-2 hover:decoration-accent"
    >
      {@address}
    </.link>
    <span
      :if={not WebAddress.acceptable?(@address)}
      data-part="address"
      class="text-xs font-normal break-all text-on-app-2"
    >
      {@address}
    </span>
    """
  end

  defp site_row(site) do
    {state, page, page_count} = site_state(site)

    base = %{
      state: state,
      message: Map.get(@site_states, state),
      address: nil,
      note: nil,
      linking_sites: site |> linking_sites_of() |> count_or_missing()
    }

    case page do
      %ScannedPage{url: url, facts: facts} ->
        base
        |> Map.merge(figures(PageFacts.comparison(facts)))
        |> Map.merge(%{address: url, note: page_note(page_count), states_price: @missing})

      nil ->
        base
    end
  end

  defp site_state(nil), do: {:no_scan, nil, 0}
  defp site_state(%{scan_status: :scanning}), do: {:scanning, nil, 0}
  defp site_state(%{scan_status: :failed}), do: {:failed, nil, 0}
  defp site_state(%{matched?: false}), do: {:not_matched, nil, 0}
  defp site_state(%{pages: []}), do: {:no_page, nil, 0}
  defp site_state(%{pages: [first | _more] = pages}), do: {:page, first, length(pages)}

  defp linking_sites_of(%{linking_sites: count}), do: count
  defp linking_sites_of(nil), do: nil

  defp page_note(1), do: nil
  defp page_note(count), do: "1 of #{count} pages about this topic"

  defp competitor_row(%CompetitorPage{} = page) do
    address = page.read_url || page.url

    page.facts
    |> figures()
    |> Map.merge(%{
      id: "page-comparison-competitor-#{page.id}",
      outcome: page.outcome,
      domain: HostName.to_unicode(page.domain),
      href: if(web_url?(address), do: address),
      note: if(page.outcome == :unreadable, do: "This page could not be opened"),
      states_price: states_price(page.outcome),
      linking_sites: count_or_missing(page.linking_sites)
    })
  end

  defp figures(nil), do: %{words: @missing, headings: @missing, structured_data: @missing, types: nil, contact: @missing}

  defp figures(comparison) do
    types = comparison["structured_data_types"] |> List.wrap() |> Enum.filter(&is_binary/1)

    %{
      words: count_or_missing(comparison["word_count"]),
      headings: headings(comparison["main_heading_count"], comparison["sub_heading_count"]),
      structured_data: if(types == [], do: "No", else: "Yes"),
      types: if(types != [], do: Enum.join(types, ", ")),
      contact: contact(comparison["ways_to_act"])
    }
  end

  defp headings(main, sub) when is_integer(main) and is_integer(sub), do: "#{main} main, #{sub} smaller"
  defp headings(_main, _sub), do: @missing

  defp contact(ways) when is_map(ways) do
    case for({key, name} <- @contact_kinds, is_integer(ways[key]) and ways[key] > 0, do: name) do
      [] -> "None"
      [first | rest] -> Enum.join([String.capitalize(first) | rest], ", ")
    end
  end

  defp contact(_unknown), do: @missing

  defp states_price(:prices_found), do: "Yes"
  defp states_price(:no_prices), do: "No"
  defp states_price(_unreadable), do: @missing

  defp count_or_missing(count) when is_integer(count) and count >= 0, do: Format.integer(count)
  defp count_or_missing(_unknown), do: @missing

  defp web_url?("http://" <> _rest), do: true
  defp web_url?("https://" <> _rest), do: true
  defp web_url?(_other), do: false
end
