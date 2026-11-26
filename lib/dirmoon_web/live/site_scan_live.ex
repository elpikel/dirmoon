defmodule DirmoonWeb.SiteScanLive do
  @moduledoc """
  "Your site" (`/app/runs/:id/site`), in the app shell: what the Site Scan
  of an Existing Site run found, under one plain question per group of
  Findings, the topics people search for first (what only dirmoon can tell
  the owner). Within a question, problems, then warnings, then checks not
  made, with the good news folded away; each Finding says what it means and
  what to do (`DirmoonWeb.SiteScanAdvice`) and lists the pages, topics or
  searches it concerns.

  While the scan reads the site it shows how many pages are read, updating
  live from the scan's PubSub topic; each update then loads only the scan's
  status (`Dirmoon.SiteScans.report/2` gives no Findings while it scans),
  and the questions and their Findings appear once it ends. A failed scan, or one whose reading
  stopped part-way (`Dirmoon.SiteScans.stale?/1`), shows why and a button
  that runs it again (`Dirmoon.SiteScans.retry/2`).
  A run without a site (a New Idea run) shows that it has none; another
  Account's run is not found.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Format
  alias Dirmoon.Research.Run
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.SiteScan
  alias Dirmoon.WebPage.HostName
  alias Dirmoon.WebPage.WebAddress
  alias DirmoonWeb.RunDisplay
  alias DirmoonWeb.SiteScanAdvice

  @not_found_message "Research not found"
  @page_forms %{one: "page", other: "pages"}
  @niche_forms %{one: "topic", other: "topics"}
  @phrase_forms %{one: "search", other: "searches"}
  @time_forms %{one: "time", other: "times"}

  @level_marker_classes %{
    problem: "bg-warn text-ink border-warn",
    warning: "border-warn text-warn",
    not_checked: "border-app-line-strong text-on-app-muted",
    good: "border-accent text-accent"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:runs}
      context={@context_line}
      note={RunDisplay.mode_label(@run.mode)}
    >
      <:status><span id="site-scan-status-line">{@status_line}</span></:status>
      <section id="site-scan" class="flex min-w-0 grow flex-col gap-6 px-7 pt-6 pb-10 max-sm:px-4">
        <nav aria-label="Research" class="flex flex-wrap gap-x-5 gap-y-1 text-sm">
          <.link
            id="site-scan-results-link"
            navigate={RunDisplay.results_path(@run)}
            class="inline-flex min-h-target-min items-center text-on-app-2 underline decoration-app-line-strong underline-offset-4 transition-colors duration-150 hover:text-on-app hover:decoration-accent"
          >
            Back to the topics
          </.link>
          <.link
            id="site-scan-run-link"
            navigate={~p"/app/runs/#{@run}"}
            class="inline-flex min-h-target-min items-center text-on-app-2 underline decoration-app-line-strong underline-offset-4 transition-colors duration-150 hover:text-on-app hover:decoration-accent"
          >
            The research
          </.link>
        </nav>

        <div :if={is_nil(@scan)} id="site-scan-empty" class="flex max-w-[640px] flex-col gap-2">
          <h1 class="m-0 text-[22px] leading-snug font-bold">This research has no site.</h1>
          <p class="m-0 text-[15px] leading-normal text-on-app-2">
            I read and check a site only for research about a business that already has one. Start a new research with your site's address to see what I find on it.
          </p>
        </div>

        <%= if @scan do %>
          <h1 class="m-0 min-w-0 text-[22px] leading-snug font-bold break-words">
            Your site: {HostName.to_unicode(@run.domain)}
          </h1>

          <div
            :if={@scan.status == :scanning and not @stale?}
            id="site-scan-progress"
            role="status"
            class="flex min-w-0 flex-col gap-1 rounded-tile border border-app-line-strong bg-app-raised px-4 py-3.5"
          >
            <span class="min-w-0 text-[15px] font-medium break-words">{@progress_line}</span>
            <span class="text-sm text-on-app-muted">
              The checks appear here once I've read the site. You can leave this page; I'll keep going.
            </span>
          </div>

          <div
            :if={@scan.status == :failed or @stale?}
            id="site-scan-failed"
            class="flex min-w-0 flex-col items-start gap-3 rounded-tile border border-warn bg-app-raised px-4 py-4"
          >
            <span class="max-w-full min-w-0 text-[17px] leading-snug font-bold break-words text-warn">
              {if(@stale?,
                do: "My reading of your site stopped part-way.",
                else: "I couldn't read #{HostName.to_unicode(@run.domain)}."
              )}
            </span>
            <p :if={@stale?} class="m-0 text-sm leading-normal text-on-app-2">
              I haven't stored anything new for a while, so my reading stopped on my side. Press the button and I'll pick it up where it stopped.
            </p>
            <p
              :if={not @stale?}
              id="site-scan-error"
              class="m-0 text-sm leading-normal break-words text-on-app-2"
            >
              {@scan.error}
            </p>
            <p :if={not @stale?} class="m-0 text-sm leading-normal text-on-app-muted">
              Run it again and I'll read only the pages I haven't read yet.
            </p>
            <.button
              id="retry-site-scan"
              variant="lime"
              size="large"
              phx-click="retry"
              phx-disable-with="Starting…"
            >
              Read my site again
            </.button>
          </div>

          <dl
            :if={@findings != []}
            id="site-scan-summary"
            class="m-0 grid grid-cols-[repeat(auto-fit,minmax(min(130px,100%),1fr))] gap-2.5"
          >
            <div
              :for={level <- Finding.levels()}
              id={"site-scan-summary-#{level}"}
              class="flex flex-col gap-1 rounded-tile border border-app-line-strong bg-app-raised px-4 py-3"
            >
              <dt class="text-xs text-on-app-2">{SiteScanAdvice.level_label(level)}</dt>
              <dd class={[
                "m-0 text-[24px] font-extrabold tracking-[-0.03em]",
                level_text_class(level)
              ]}>
                {Map.get(@level_counts, level, 0)}
              </dd>
            </div>
          </dl>

          <section
            :for={question <- @questions}
            :if={@scan.status != :scanning}
            id={"question-#{question.question}"}
            class="flex min-w-0 flex-col gap-3"
          >
            <h2 class="m-0 text-[17px] leading-snug font-bold">{question.heading}</h2>
            <p
              :if={question.to_show == [] and question.fine == []}
              id={"question-#{question.question}-empty"}
              class="m-0 text-sm text-on-app-muted"
            >
              I have nothing to say about this.
            </p>
            <.finding_card :for={finding <- question.to_show} finding={finding} run={@run} />
            <details
              :if={question.fine != []}
              id={"question-#{question.question}-fine"}
              class="rounded-tile border border-app-line bg-app-raised/40"
            >
              <summary class="flex min-h-target-min cursor-pointer items-center px-4 text-sm font-medium text-accent">
                What's fine ({length(question.fine)})
              </summary>
              <div class="flex flex-col gap-3 border-t border-app-line p-3">
                <.finding_card :for={finding <- question.fine} finding={finding} run={@run} />
              </div>
            </details>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case SiteScans.report(socket.assigns.current_scope, id) do
      {:ok, %{run: run} = report} ->
        if connected?(socket), do: SiteScans.subscribe(run)
        {:ok, assign_report(socket, report)}

      {:error, :not_found} ->
        {:ok, redirect_not_found(socket)}
    end
  end

  @impl true
  def handle_info({:site_scan_updated, _run_id}, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("retry", _params, socket) do
    case SiteScans.retry(socket.assigns.current_scope, socket.assigns.run.id) do
      {:ok, %SiteScan{}} -> {:noreply, reload(socket)}
      {:error, :not_found} -> {:noreply, redirect_not_found(socket)}
    end
  end

  attr :finding, :map, required: true
  attr :run, Run, required: true

  defp finding_card(assigns) do
    ~H"""
    <article
      id={@finding.dom_id}
      data-level={@finding.level}
      class="flex min-w-0 flex-col gap-2 rounded-tile border border-app-line-strong bg-app-raised px-4 py-3.5"
    >
      <div class="flex flex-wrap items-start gap-x-3 gap-y-1.5">
        <span
          data-part="level"
          class={[
            "flex-none rounded-pill border px-[9px] py-[3px] font-mono text-[11px] whitespace-nowrap",
            level_marker_class(@finding.level)
          ]}
        >
          {SiteScanAdvice.level_label(@finding.level)}
        </span>
        <h3
          data-part="title"
          class="m-0 min-w-0 flex-[1_1_220px] text-[15px] leading-snug font-semibold break-words"
        >
          {@finding.sentences.title}
        </h3>
      </div>
      <p data-part="meaning" class="m-0 text-sm leading-normal break-words text-on-app-2">
        <span class="text-on-app-muted">What it means: </span>{@finding.sentences.meaning}
      </p>
      <p
        :if={@finding.sentences.action}
        data-part="action"
        class="m-0 text-sm leading-normal break-words text-on-app"
      >
        <span class="text-on-app-muted">What to do: </span>{@finding.sentences.action}
      </p>
      <.finding_list finding={@finding} run={@run} />
    </article>
    """
  end

  attr :finding, :map, required: true
  attr :run, Run, required: true

  defp finding_list(%{finding: %{list: {:niches, niches}}} = assigns) do
    assigns = assign(assigns, niches: niches, summary: show_label(assigns.finding.list_total, @niche_forms))

    ~H"""
    <details id={"#{@finding.dom_id}-niches"} class="text-sm">
      <summary class="flex min-h-target-min cursor-pointer items-center text-on-app-2 hover:text-on-app">
        {@summary}
      </summary>
      <ul class="m-0 flex list-none flex-col gap-2.5 p-0">
        <li :for={niche <- @niches} data-part="niche" class="flex min-w-0 flex-col gap-0.5">
          <.link
            navigate={~p"/app/runs/#{@run}/results?#{[view: "niches", niche: niche.id]}"}
            class="font-medium break-words text-on-app underline decoration-app-line-strong underline-offset-2 hover:decoration-accent"
          >
            {niche.name}
          </.link>
          <span :if={niche.volume} class="text-xs text-on-app-muted">{niche.volume}</span>
          <.page_links :if={niche.pages != []} pages={niche.pages} />
        </li>
      </ul>
      <p :if={@finding.more > 0} data-part="more" class="m-0 mt-2 text-xs text-on-app-muted">
        and {@finding.more} more
      </p>
    </details>
    """
  end

  defp finding_list(%{finding: %{list: {:phrases, phrases}}} = assigns) do
    assigns = assign(assigns, phrases: phrases, summary: show_label(assigns.finding.list_total, @phrase_forms))

    ~H"""
    <details id={"#{@finding.dom_id}-phrases"} class="text-sm">
      <summary class="flex min-h-target-min cursor-pointer items-center text-on-app-2 hover:text-on-app">
        {@summary}
      </summary>
      <ul class="m-0 flex list-none flex-col gap-2.5 p-0">
        <li :for={phrase <- @phrases} data-part="phrase" class="flex min-w-0 flex-col gap-0.5">
          <span class="font-medium break-words">
            “{phrase.phrase}”
            <span class="font-mono text-xs text-on-app-muted">{phrase.position}</span>
          </span>
          <.page_links :if={phrase.pages != []} pages={phrase.pages} />
        </li>
      </ul>
      <p :if={@finding.more > 0} data-part="more" class="m-0 mt-2 text-xs text-on-app-muted">
        and {@finding.more} more
      </p>
    </details>
    """
  end

  defp finding_list(%{finding: %{list: {:pages, pages}}} = assigns) do
    assigns = assign(assigns, pages: pages, summary: show_label(assigns.finding.list_total, @page_forms))

    ~H"""
    <details id={"#{@finding.dom_id}-pages"} class="text-sm">
      <summary class="flex min-h-target-min cursor-pointer items-center text-on-app-2 hover:text-on-app">
        {@summary}
      </summary>
      <.page_links pages={@pages} />
      <p :if={@finding.more > 0} data-part="more" class="m-0 mt-2 text-xs text-on-app-muted">
        and {@finding.more} more
      </p>
    </details>
    """
  end

  defp finding_list(assigns), do: ~H""

  attr :pages, :list, required: true

  defp page_links(assigns) do
    ~H"""
    <ul class="m-0 flex list-none flex-col gap-1 p-0">
      <li :for={page <- @pages} data-part="page" class="min-w-0 break-all">
        <.link
          :if={page.link?}
          href={page.address}
          target="_blank"
          rel="noopener noreferrer nofollow"
          class="text-on-app-2 underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:text-on-app hover:decoration-accent"
        >
          {page.address}
        </.link>
        <span :if={not page.link?} class="text-on-app-2">{page.address}</span>
      </li>
    </ul>
    """
  end

  defp reload(socket) do
    case SiteScans.report(socket.assigns.current_scope, socket.assigns.run.id) do
      {:ok, report} -> assign_report(socket, report)
      {:error, :not_found} -> redirect_not_found(socket)
    end
  end

  defp assign_report(socket, %{run: run, scan: scan, findings: findings}) do
    shown = shown_findings(findings)

    assign(socket,
      page_title: "Your site · #{RunDisplay.short_description(run.description)}",
      run: run,
      scan: scan,
      findings: findings,
      stale?: scan != nil and SiteScans.stale?(scan),
      context_line: RunDisplay.context_line(run),
      status_line: SiteScanAdvice.status_line(%{scan: scan, domain: HostName.to_unicode(run.domain), findings: findings}),
      progress_line: scan && SiteScanAdvice.progress_line(scan, HostName.to_unicode(run.domain)),
      level_counts: Enum.frequencies_by(findings, & &1.level),
      questions: Enum.map(SiteScanAdvice.questions_in_screen_order(), &question_section(&1, shown))
    )
  end

  defp question_section(question, shown) do
    {fine, to_show} = shown |> Enum.filter(&(&1.question == question)) |> Enum.split_with(&(&1.level == :good))
    %{question: question, heading: SiteScanAdvice.question(question), to_show: to_show, fine: fine}
  end

  defp shown_findings(findings) do
    repeated_checks = findings |> Enum.frequencies_by(& &1.check) |> Map.filter(fn {_check, count} -> count > 1 end)

    {shown, _numbers} =
      Enum.map_reduce(findings, %{}, fn finding, numbers ->
        number = Map.get(numbers, finding.check, 0) + 1
        {shown_finding(finding, dom_id(finding.check, number, repeated_checks)), Map.put(numbers, finding.check, number)}
      end)

    shown
  end

  defp dom_id(check, number, repeated_checks) when is_map_key(repeated_checks, check), do: "finding-#{check}-#{number}"
  defp dom_id(check, _number, _repeated_checks), do: "finding-#{check}"

  defp shown_finding(%Finding{} = finding, dom_id) do
    {list, list_total} = finding_items(finding)

    %{
      dom_id: dom_id,
      question: finding.question,
      level: finding.level,
      sentences: SiteScanAdvice.sentences(finding),
      list: list,
      list_total: list_total,
      more: max(list_total - list_length(list), 0)
    }
  end

  defp finding_items(%Finding{figures: %{niches: [_one | _more] = niches} = figures}) do
    items =
      for %{name: name} = niche when is_binary(name) <- niches do
        %{id: niche.id, name: name, volume: typed(niche[:volume]), pages: page_items(niche[:pages])}
      end

    {{:niches, items}, total(figures[:niche_count], items)}
  end

  defp finding_items(%Finding{figures: %{phrases: [_one | _more] = phrases} = figures}) do
    items =
      for %{phrase: phrase} = entry when is_binary(phrase) <- phrases do
        %{phrase: phrase, position: position(entry[:position]), pages: page_items(List.wrap(entry[:url]))}
      end

    {{:phrases, items}, total(figures[:phrase_count], items)}
  end

  defp finding_items(%Finding{pages: [_one | _more] = pages, page_count: page_count}) do
    items = page_items(pages)
    {{:pages, items}, total(page_count, items)}
  end

  defp finding_items(%Finding{}), do: {nil, 0}

  defp list_length({_kind, items}), do: length(items)
  defp list_length(nil), do: 0

  defp total(count, items) when is_integer(count), do: max(count, length(items))
  defp total(_count, items), do: length(items)

  defp page_items(pages) when is_list(pages) do
    for address when is_binary(address) <- pages, do: %{address: address, link?: WebAddress.acceptable?(address)}
  end

  defp page_items(_not_a_list), do: []

  defp typed(volume) when is_integer(volume),
    do: "typed #{Format.integer(volume)} #{Format.plural(volume, @time_forms)} a month"

  defp typed(nil), do: nil

  defp position(%Decimal{} = position), do: "position #{Format.decimal(position, 1)}"

  defp show_label(1, %{one: one}), do: "Show the #{one}"
  defp show_label(count, %{other: other}), do: "Show the #{Format.integer(count)} #{other}"

  defp level_marker_class(level), do: Map.fetch!(@level_marker_classes, level)

  defp level_text_class(:good), do: "text-accent"
  defp level_text_class(:not_checked), do: "text-on-app-muted"
  defp level_text_class(_problem_or_warning), do: "text-warn"

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, @not_found_message)
    |> push_navigate(to: ~p"/app/runs")
  end
end
