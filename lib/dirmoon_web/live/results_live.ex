defmodule DirmoonWeb.ResultsLive do
  @moduledoc """
  Screen 3, Results (`/app/runs/:id/results`): the headline stating the
  outcome, and one dark panel in three columns modelled on an inbox: the
  views (Niches, all kept Phrases, Rejected Phrases) with the run's
  parameters; the list of the chosen view; and the
  selected Niche with its stat tiles, its Phrases and the actions to choose
  or reject it. The view and the selected Niche live in the URL
  (`?view=niches|phrases|rejected&niche=<id>`). An Existing Site run's
  views also lead to "Your site" (`DirmoonWeb.SiteScanLive`), and once its
  Site Scan's pages are matched to the Niches each topic says whether the
  site has a page for it; once a Price Check has read a Niche's Competitor
  Pages, the Niche compares the site's page with them
  (`DirmoonWeb.PageComparison`). The screen follows the run, its Price
  Checks and, for an Existing Site, its Site Scan live.

  Before Step 7 has finished (`Run.results_ready?/1`) it shows the Phrases so
  far without any Niche choice, and turns into the full results when the run
  says Step 7 is done. See `docs/design/README.md` section 8.3 and
  `docs/design/reference/results.html`.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Format
  alias Dirmoon.Niches
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Niches.Scoring
  alias Dirmoon.Pages.Page
  alias Dirmoon.Phrases
  alias Dirmoon.PriceChecks
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.StatusLine
  alias Dirmoon.SiteScans
  alias Dirmoon.WebPage.HostName
  alias Dirmoon.WebPage.WebAddress
  alias DirmoonWeb.NicheAdvice
  alias DirmoonWeb.PageComparison
  alias DirmoonWeb.PageDisplay
  alias DirmoonWeb.ResultsHeadline
  alias DirmoonWeb.RunDisplay

  @not_found_message "Research not found"
  @list_limit 500
  @niche_phrases_preview 10
  @missing "—"
  @serp_size 10
  @sites_in_row 3

  @page_type_meanings [
    direct_competitor: "Businesses offering the same as you. The hardest to get ahead of.",
    portal: "Classifieds, city and news sites.",
    directory: "Business listings and comparison sites.",
    blog: "Articles and guides, not offers. A business's page usually beats them.",
    forum: "Forums and question-and-answer sites. A business's page usually beats them."
  ]
  @phrase_forms %{one: "search", other: "searches"}
  @niche_forms %{one: "topic", other: "topics"}
  @result_forms %{one: "result", other: "results"}
  @quick_win_forms %{one: "quick win", other: "quick wins"}

  @page_forms %{one: "page", other: "pages"}

  @price_check_errors %{
    not_found: "Topic not found",
    run_not_ready: "I'll check prices when the results are ready",
    no_competitors: "No business like yours is on Google's first page, so I have no prices to check"
  }

  @reject_errors %{
    not_found: "Topic not found",
    not_rejectable: "This topic can no longer be rejected"
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
      <:status><span id="results-status-line">{@status_line}</span></:status>
      <section id="results" class="flex grow flex-col min-[860px]:flex-row min-[860px]:flex-wrap">
        <div class="box-border flex flex-[1_1_190px] flex-col gap-5 border-app-line px-3 py-4 min-[860px]:border-r max-[859px]:border-b">
          <nav id="results-views" aria-label="Views" class="flex flex-col gap-1">
            <span class="px-3 pb-1 font-mono text-[10px] uppercase tracking-[0.1em] text-on-app-muted">
              What I found
            </span>
            <.view_link
              id="view-niches"
              label="Topics"
              hint="Searches about the same thing, put together. Start here."
              count={@counts.niches}
              active={@view == :niches}
              patch={@ready? && view_path(@run, %{view: "niches", niche: @selected_id})}
            />
            <.view_link
              id="view-phrases"
              label="All searches"
              hint="Each exact thing people type into Google, and how often."
              count={@counts.kept}
              active={@view == :phrases}
              patch={view_path(@run, %{view: "phrases", niche: @selected_id})}
            />
            <.view_link
              id="view-rejected"
              label="Searches I left out"
              hint="Searches I didn't use, and why."
              count={@counts.rejected}
              active={@view == :rejected}
              patch={@ready? && view_path(@run, %{view: "rejected", niche: @selected_id})}
            />
            <.view_link
              :if={@run.mode == :existing_site}
              id="view-site"
              label="Your site"
              hint="What I found on your own site, and what to fix."
              active={false}
              navigate={~p"/app/runs/#{@run}/site"}
            />
          </nav>
          <div id="run-parameters" class="flex flex-col gap-2.5 px-3 text-xs">
            <span class="font-mono text-[10px] uppercase tracking-[0.1em] text-on-app-muted">
              What you asked about
            </span>
            <p
              id="run-description"
              class="m-0 border-l-2 border-accent pl-3 text-[13px] leading-normal break-words whitespace-pre-line text-on-app"
            >
              {@run.description}
            </p>
            <span class="font-mono text-on-app-2">{RunDisplay.market(@run)}</span>
            <span :if={@run.city} class="font-mono text-on-app-2">{@run.city}</span>
            <span :if={@run.mode == :existing_site} class="font-mono text-on-app-2">{HostName.to_unicode(
              @run.domain
            )}</span>
            <span :if={@run.priority_services != []} id="run-services" class="text-on-app-2">
              Services: {Enum.join(@run.priority_services, ", ")}
            </span>
          </div>
        </div>

        <div class="flex min-w-0 flex-[3_1_250px] flex-col border-app-line min-[860px]:border-r max-[859px]:border-b">
          <h1
            id="results-headline"
            class="m-0 border-b border-app-line px-[18px] py-3.5 text-[15px] leading-snug font-bold"
          >
            {@headline}
          </h1>
          <p
            :if={@ready?}
            id="results-explainer"
            class="m-0 border-b border-app-line px-[18px] py-3 text-[13px] leading-normal text-on-app-2"
          >
            {view_explainer(@view)}
          </p>
          <.niche_list
            :if={@view == :niches}
            niches={@streams.niches}
            low_count={@low_count}
            show_low_niches={@show_low_niches}
          />
          <.phrase_list
            :if={@view == :phrases}
            id="phrases"
            rows={@streams.phrases}
            shown={min(@counts.kept, @list_limit)}
            total={@counts.kept}
            empty="No searches yet."
          />
          <.phrase_list
            :if={@view == :rejected}
            id="rejected-phrases"
            rows={@streams.rejected_phrases}
            shown={min(@counts.rejected, @list_limit)}
            total={@counts.rejected}
            empty="I left no search out."
          />
        </div>

        <div class="flex min-w-0 flex-[6_1_400px] flex-col gap-5 px-7 pt-6 pb-7 max-sm:px-5">
          <.not_ready :if={not @ready?} run={@run} />
          <div
            :if={@ready? and is_nil(@selected)}
            id="niche-detail-empty"
            class="flex flex-col gap-2"
          >
            <span class="text-[22px] leading-snug font-bold">No topic to choose.</span>
            <p class="m-0 text-[15px] leading-normal text-on-app-muted">
              Every search, and why I left some out, is in the views on the left.
            </p>
          </div>
          <.niche_detail
            :if={@ready? and @selected}
            run={@run}
            selected={@selected}
            choosable?={@choosable?}
            detail={@detail}
            niche_phrases={@streams.niche_phrases}
            phrase_total={length(@detail.phrases)}
            show_all_niche_phrases={@show_all_niche_phrases}
            price_check={@price_check}
            competitor_page_count={@competitor_page_count}
            page_comparison={@page_comparison}
            site_page={site_page(@site_pages, @selected.niche.id)}
          />
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Research.get_run(socket.assigns.current_scope, id) do
      %Run{} = run ->
        if connected?(socket), do: subscribe(run)

        {:ok,
         socket
         |> assign(run: run, show_low_niches: false, show_all_niche_phrases: false)
         |> stream_configure(:niches, dom_id: &"niche-row-#{&1.id}")
         |> stream_configure(:phrases, dom_id: &"phrases-#{&1.id}")
         |> stream_configure(:rejected_phrases, dom_id: &"rejected-phrases-#{&1.id}")
         |> stream_configure(:niche_phrases, dom_id: &"niche-phrases-#{&1.id}")}

      nil ->
        {:ok, redirect_not_found(socket)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    requested = %{view: requested_view(params), niche_id: requested_niche_id(params)}

    {:noreply,
     socket
     |> assign(requested: requested, show_all_niche_phrases: false)
     |> load_results()}
  end

  @impl true
  def handle_info({:run_updated, _run_id}, socket) do
    %{current_scope: scope, run: run} = socket.assigns

    case Research.get_run(scope, run.id) do
      %Run{} = updated_run -> {:noreply, socket |> assign(:run, updated_run) |> load_results()}
      nil -> {:noreply, redirect_not_found(socket)}
    end
  end

  def handle_info({:run_progress, _run_id, _progress}, socket), do: {:noreply, socket}

  def handle_info({:price_check_updated, _niche_id}, socket), do: {:noreply, load_results(socket)}

  def handle_info({:site_scan_updated, _run_id}, socket), do: {:noreply, load_results(socket)}

  @impl true
  def handle_event("choose", _params, %{assigns: %{choosable?: true, selected: %{niche: %Niche{id: niche_id}}}} = socket) do
    case Niches.choose(socket.assigns.current_scope, niche_id) do
      {:ok, page} ->
        page_path = RunDisplay.page_path(page)
        {:noreply, push_navigate(socket, to: page_path)}

      {:error, reason} ->
        message = PageDisplay.choose_error(reason)
        {:noreply, socket |> put_flash(:error, message) |> load_results()}
    end
  end

  def handle_event("reject", _params, %{assigns: %{choosable?: true, selected: %{niche: %Niche{id: niche_id}}}} = socket) do
    case Niches.reject(socket.assigns.current_scope, niche_id) do
      {:ok, _rejected_niche} ->
        %{run: run, offered_ids: offered_ids} = socket.assigns
        next_niche_id = next_niche_id(offered_ids, niche_id)
        next_path = view_path(run, %{view: "niches", niche: next_niche_id})

        {:noreply,
         socket
         |> put_flash(:info, "I rejected the topic.")
         |> push_patch(to: next_path)}

      {:error, reason} ->
        message = Map.fetch!(@reject_errors, reason)
        {:noreply, socket |> put_flash(:error, message) |> load_results()}
    end
  end

  def handle_event("check_prices", _params, %{assigns: %{selected: %{niche: %Niche{id: niche_id}}}} = socket) do
    case PriceChecks.start(socket.assigns.current_scope, niche_id) do
      {:ok, _price_check} ->
        {:noreply, load_results(socket)}

      {:error, reason} ->
        message = Map.fetch!(@price_check_errors, reason)
        {:noreply, socket |> put_flash(:error, message) |> load_results()}
    end
  end

  def handle_event("show_low_niches", _params, socket) do
    {:noreply, socket |> assign(:show_low_niches, true) |> load_results()}
  end

  def handle_event("show_all_niche_phrases", _params, socket) do
    {:noreply, socket |> assign(:show_all_niche_phrases, true) |> load_results()}
  end

  def handle_event(action, _params, socket) when action in ["choose", "reject", "check_prices"], do: {:noreply, socket}

  defp view_explainer(:niches) do
    "People ask Google for the same thing in many different words. A topic is those searches put together. " <>
      "Each row is one topic, the best first. Click a topic to see its searches and who is on Google's first page, " <>
      "then choose it and I'll write the plan and the text for one page about it."
  end

  defp view_explainer(:phrases) do
    "Every search I kept: what people type into Google, how many times a month they type it " <>
      "and what businesses pay Google for one ad click."
  end

  defp view_explainer(:rejected), do: "Searches I left out of the topics, each with the reason."

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true, doc: "one line saying what the view holds"
  attr :count, :integer, default: nil, doc: "how many items the view holds"
  attr :active, :boolean, required: true
  attr :patch, :any, default: nil, doc: "where the view leads, false when it isn't available yet"
  attr :navigate, :string, default: nil, doc: "another screen the link leads to, instead of a view of this one"

  defp view_link(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="flex min-h-target-min items-start justify-between gap-3 rounded-[8px] px-3 py-2.5 text-sm font-medium text-on-app-muted no-underline transition-colors duration-150 hover:bg-app-raised hover:text-on-app"
    >
      <span class="flex flex-col gap-0.5">
        <span>{@label}</span>
        <span data-part="hint" class="text-xs leading-snug font-normal text-on-app-muted">{@hint}</span>
      </span>
      <.icon name="hero-arrow-right-mini" class="size-4 flex-none" />
    </.link>
    """
  end

  defp view_link(%{patch: false} = assigns) do
    ~H"""
    <span
      id={@id}
      aria-disabled="true"
      class="flex min-h-target-min items-start justify-between gap-3 rounded-[8px] px-3 py-2.5 text-sm font-medium text-on-app-muted opacity-60"
    >
      <span class="flex flex-col gap-0.5">
        <span>{@label}</span>
        <span data-part="hint" class="text-xs leading-snug font-normal">{@hint}</span>
      </span>
      <span data-part="count" class="font-mono text-[11px]">{@count}</span>
    </span>
    """
  end

  defp view_link(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@active && "page"}
      class={[
        "flex min-h-target-min items-start justify-between gap-3 rounded-[8px] px-3 py-2.5 text-sm font-medium no-underline transition-colors duration-150",
        if(@active,
          do: "bg-app-selected text-on-app",
          else: "text-on-app-muted hover:bg-app-raised hover:text-on-app"
        )
      ]}
    >
      <span class="flex flex-col gap-0.5">
        <span>{@label}</span>
        <span data-part="hint" class="text-xs leading-snug font-normal text-on-app-muted">{@hint}</span>
      </span>
      <span
        data-part="count"
        class={[
          "font-mono text-[11px]",
          @active && "rounded-pill bg-accent px-[7px] py-0.5 text-ink"
        ]}
      >
        {@count}
      </span>
    </.link>
    """
  end

  attr :niches, :any, required: true
  attr :low_count, :integer, required: true
  attr :show_low_niches, :boolean, required: true

  defp niche_list(assigns) do
    ~H"""
    <ul id="niches" phx-update="stream" class="m-0 flex list-none flex-col p-0">
      <li id="niches-empty" class="hidden px-[18px] py-4 text-sm text-on-app-muted only:block">
        No topic has a rating of 4 out of 10 or higher.
      </li>
      <li :for={{dom_id, row} <- @niches} id={dom_id} class="border-b border-app-line">
        <.link
          patch={row.path}
          aria-current={row.selected? && "true"}
          data-selected={row.selected?}
          class={[
            "flex min-h-target-min flex-col gap-2 px-[18px] py-4 no-underline transition-colors duration-150",
            if(row.selected?, do: "bg-app-raised", else: "hover:bg-app-raised")
          ]}
        >
          <span data-part="advice" class={["text-xs font-medium", row.advice_class]}>
            {row.advice}
          </span>
          <span class={[
            "text-sm leading-snug font-medium",
            if(row.selected?, do: "text-on-app", else: "text-on-app-2")
          ]}>
            {row.name}
          </span>
          <span data-part="figures" class="text-xs text-on-app-muted">{row.figures}</span>
          <span
            :if={row.site_page != :unknown}
            id={"#{dom_id}-site-page"}
            data-part="site-page"
            class="min-w-0 text-xs break-all text-on-app-2"
          >
            {if(row.site_page, do: "You have a page: #{row.site_page}", else: "No page yet")}
          </span>
        </.link>
      </li>
    </ul>
    <button
      :if={@low_count > 0 and not @show_low_niches}
      id="collapsed-niches"
      type="button"
      phx-click="show_low_niches"
      class="min-h-12 cursor-pointer border-0 bg-transparent px-[18px] text-left font-mono text-xs text-on-app-muted transition-colors duration-150 hover:text-on-app"
    >
      + {@low_count} {low_niches_label(@low_count)}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :shown, :integer, required: true
  attr :total, :integer, required: true
  attr :empty, :string, required: true

  defp phrase_list(assigns) do
    ~H"""
    <ul id={@id} phx-update="stream" class="m-0 flex list-none flex-col p-0">
      <li id={"#{@id}-empty"} class="hidden px-[18px] py-4 text-sm text-on-app-muted only:block">
        {@empty}
      </li>
      <li
        :for={{dom_id, row} <- @rows}
        id={dom_id}
        class="flex flex-col gap-1.5 border-b border-app-line px-[18px] py-3.5"
      >
        <span class="text-sm leading-snug font-medium text-on-app">{row.phrase}</span>
        <span class="flex flex-wrap items-center gap-2 font-mono text-[11px] text-on-app-muted">
          {row.figures}<.quick_win_pill :if={row.quick_win?} id={"#{dom_id}-quick-win"} />
        </span>
        <span :if={row.note} class="text-xs text-on-app-2">{row.note}</span>
      </li>
    </ul>
    <p :if={@total > @shown} class="m-0 px-[18px] py-3.5 font-mono text-[11px] text-on-app-muted">
      Showing the first {@shown} of {@total}.
    </p>
    """
  end

  attr :id, :string, required: true

  defp quick_win_pill(assigns) do
    ~H"""
    <span
      id={@id}
      data-part="quick-win"
      class="rounded-pill border border-accent px-[7px] py-px font-mono text-[10px] leading-4 whitespace-nowrap text-accent"
    >
      quick win
    </span>
    """
  end

  attr :run, Run, required: true

  defp not_ready(assigns) do
    ~H"""
    <div id="results-not-ready" class="flex flex-col items-start gap-3">
      <span class="text-[22px] leading-snug font-bold">The topics are still taking shape.</span>
      <p class="m-0 text-[15px] leading-normal text-on-app-muted">
        Showing the searches I collected so far. Topics to choose from will show up here when I finish rating them (step 7).
      </p>
      <.button id="back-to-run" variant="outline" size="large" navigate={~p"/app/runs/#{@run}"}>
        Back to the research
      </.button>
    </div>
    """
  end

  attr :run, Run, required: true
  attr :selected, :map, required: true
  attr :choosable?, :boolean, required: true
  attr :detail, :map, required: true
  attr :niche_phrases, :any, required: true
  attr :phrase_total, :integer, required: true
  attr :show_all_niche_phrases, :boolean, required: true
  attr :price_check, PriceCheck, default: nil
  attr :competitor_page_count, :integer, required: true
  attr :page_comparison, :map, default: nil
  attr :site_page, :any, required: true, doc: "the address of the site's page for the topic, nil for none, :unknown"

  defp niche_detail(assigns) do
    %{detail: %{page: page}, phrase_total: phrase_total, selected: %{niche: niche}} = assigns
    open_page = open_page(page)
    phrase_noun = Format.plural(phrase_total, @phrase_forms)
    score_label = score_label(niche.score)
    advice = NicheAdvice.advice(assigns.selected)
    assigns = assign(assigns, page: open_page, phrase_noun: phrase_noun, score_label: score_label, advice: advice)

    ~H"""
    <article id="niche-detail" data-niche-id={@selected.niche.id} class="flex flex-col gap-5">
      <div class="flex flex-col gap-2">
        <span class="font-mono text-[11px] text-on-app-muted">
          topic · {@phrase_total} {@phrase_noun} · {@score_label}<span
            :if={@detail.quick_win_count > 0}
            id="niche-quick-win-count"
          > · {@detail.quick_win_count} {quick_win_noun(@detail.quick_win_count)}</span>
        </span>
        <h2 class="m-0 text-[22px] leading-snug font-bold tracking-[-0.01em]">
          {@selected.niche.name}
        </h2>
        <p :if={@selected.niche.reading} class="m-0 text-[15px] leading-[1.55] text-on-app-muted">
          {@selected.niche.reading}
        </p>
        <p
          :if={@site_page != :unknown}
          id="niche-site-page"
          class="m-0 min-w-0 text-sm leading-normal break-all text-on-app-2"
        >
          <%= cond do %>
            <% is_nil(@site_page) -> %>
              No page yet: your site has no page about this topic.
            <% WebAddress.acceptable?(@site_page) -> %>
              You have a page:
              <.link
                href={@site_page}
                target="_blank"
                rel="noopener noreferrer nofollow"
                class="text-on-app underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:decoration-accent"
              >
                {@site_page}
              </.link>
            <% true -> %>
              You have a page: {@site_page}
          <% end %>
        </p>
      </div>

      <div
        id="niche-advice"
        data-kind={@advice.kind}
        class="flex flex-col gap-3 rounded-tile border border-app-line-strong bg-app-raised px-4 py-4"
      >
        <span id="niche-advice-label" class={["text-[17px] leading-snug font-bold", @advice.class]}>
          {@advice.label}
        </span>
        <dl class="m-0 flex flex-col gap-2.5 text-sm leading-normal">
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-on-app-muted">How many people search</dt>
            <dd id="niche-advice-demand" class="m-0 text-on-app-2">{@advice.demand}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-on-app-muted">What a customer is worth</dt>
            <dd id="niche-advice-value" class="m-0 text-on-app-2">{@advice.value}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-on-app-muted">Who answers today</dt>
            <dd id="niche-advice-competition" class="m-0 text-on-app-2">{@advice.competition}</dd>
          </div>
        </dl>
      </div>

      <div
        id="niche-stats"
        class="grid grid-cols-[repeat(auto-fit,minmax(min(140px,100%),1fr))] gap-2.5"
      >
        <.stat_tile
          id="niche-stat-volume"
          label="Times a month people type these"
          value={Format.integer(@selected.volume)}
        />
        <.stat_tile
          id="niche-stat-cpc"
          label="What businesses pay Google for one ad click"
          value={usd_or_missing(@selected.cpc)}
        />
        <.stat_tile
          :if={@run.mode == :new_idea}
          id="niche-stat-competitors"
          label="Competitors on Google's first page"
          value={competitors_or_missing(@detail.direct_competitors)}
          highlight={@detail.direct_competitors == 0}
        />
        <.stat_tile
          :if={@run.mode == :existing_site}
          id="niche-stat-position"
          label="Your best position on Google"
          value={position_or_missing(@detail.best_position)}
        />
      </div>

      <div class="flex flex-col gap-2">
        <span class="font-mono text-[11px] uppercase tracking-[0.08em] text-on-app-muted">
          What people type into Google
        </span>
        <div class="overflow-x-auto rounded-tile border border-app-line-strong bg-app-raised">
          <table class="w-full border-collapse text-sm max-[859px]:min-w-[560px]">
            <thead class="text-left font-mono text-[10px] uppercase tracking-[0.08em] text-on-app-muted">
              <tr>
                <th
                  scope="col"
                  rowspan="2"
                  class="border-b border-app-line-strong px-4 py-3 align-bottom font-medium"
                >
                  Search
                </th>
                <th
                  id="niche-phrases-volumes"
                  scope="colgroup"
                  colspan={if(@run.city, do: 2, else: 1)}
                  class="px-2.5 pt-3 pb-1 text-right font-medium normal-case tracking-normal"
                >
                  How many times a month people type it
                </th>
                <th
                  scope="col"
                  rowspan="2"
                  class="border-b border-app-line-strong px-2.5 py-3 text-right align-bottom font-medium"
                >
                  Ad click price
                </th>
                <th
                  scope="col"
                  rowspan="2"
                  class="border-b border-app-line-strong px-4 py-3 align-bottom font-medium"
                >
                  Who is on Google's first page
                </th>
                <th
                  :if={@run.mode == :existing_site}
                  id="niche-phrases-position"
                  scope="col"
                  rowspan="2"
                  class="border-b border-app-line-strong px-4 py-3 text-right align-bottom font-medium"
                >
                  Your position
                </th>
              </tr>
              <tr>
                <th
                  id="niche-phrases-country"
                  scope="col"
                  class="border-b border-app-line-strong px-2.5 pb-3 text-right font-medium"
                >
                  {@run.country_name}
                </th>
                <th
                  :if={@run.city}
                  id="niche-phrases-city"
                  scope="col"
                  class="border-b border-app-line-strong px-2.5 pb-3 text-right font-medium"
                >
                  {@run.city}
                </th>
              </tr>
            </thead>
            <tbody id="niche-phrases" phx-update="stream">
              <tr id="niche-phrases-empty" class="hidden only:table-row">
                <td colspan="6" class="px-4 py-3.5 text-on-app-muted">
                  This topic has no searches left.
                </td>
              </tr>
              <tr :for={{dom_id, row} <- @niche_phrases} id={dom_id}>
                <td class="border-t border-app-line-strong px-4 py-3 font-medium">{row.phrase}</td>
                <td class="border-t border-app-line-strong px-2.5 py-3 text-right font-mono">
                  {row.volume}
                </td>
                <td
                  :if={@run.city}
                  class="border-t border-app-line-strong px-2.5 py-3 text-right font-mono text-on-app-2"
                >
                  {row.city_volume}
                </td>
                <td class="border-t border-app-line-strong px-2.5 py-3 text-right font-mono whitespace-nowrap">
                  {row.cpc}
                </td>
                <td class="border-t border-app-line-strong px-4 py-3 break-words text-on-app-2">
                  <span :if={row.sites == []}>{row.holders}</span>
                  <span :if={row.sites != []} class="flex flex-col gap-0.5">
                    <span data-part="sites" class="text-on-app">{Enum.join(row.sites, ", ")}</span>
                    <span class="text-xs text-on-app-muted">
                      {row.holders}<a
                        :if={row.more_sites > 0}
                        data-part="more-sites"
                        href={"#first-page-#{row.id}"}
                        class="ml-1.5 text-on-app-2 underline decoration-app-line-strong underline-offset-2 hover:decoration-accent"
                      >and {row.more_sites} more</a>
                    </span>
                  </span>
                </td>
                <td
                  :if={@run.mode == :existing_site}
                  class="border-t border-app-line-strong px-4 py-3 text-right font-mono whitespace-nowrap"
                >
                  <span class="inline-flex items-center justify-end gap-2">
                    <.quick_win_pill :if={row.quick_win?} id={"#{dom_id}-quick-win"} />{row.position}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@detail.first_pages != []} id="first-pages" class="flex flex-col gap-2">
        <span class="font-mono text-[11px] uppercase tracking-[0.08em] text-on-app-muted">
          Who is on Google's first page today
        </span>
        <details
          :for={{first_page, index} <- Enum.with_index(@detail.first_pages)}
          id={"first-page-#{first_page.id}"}
          open={index == 0}
          class="rounded-tile border border-app-line-strong bg-app-raised"
        >
          <summary class="flex min-h-target-min cursor-pointer items-center justify-between gap-3 px-4 text-sm font-medium">
            <span class="flex flex-wrap items-baseline gap-x-2">
              <span data-part="first-page-label" class="text-xs font-normal text-on-app-muted">
                When someone types into Google:
              </span>
              <span data-part="first-page-phrase">“{first_page.phrase}”</span>
            </span>
            <span class="font-mono text-[11px] text-on-app-muted">
              {result_count(first_page.results)}
            </span>
          </summary>
          <p
            :if={first_page.results == []}
            class="m-0 border-t border-app-line-strong px-4 py-3 text-sm text-on-app-muted"
          >
            Google showed no results for this search.
          </p>
          <ol class="m-0 flex list-none flex-col p-0">
            <li
              :for={result <- first_page.results}
              data-part="first-page-result"
              class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 border-t border-app-line-strong px-4 py-2.5 text-sm"
            >
              <span class="w-5 shrink-0 font-mono text-[11px] text-on-app-muted">{result.position}</span>
              <span class="flex min-w-0 flex-[1_1_220px] flex-col gap-0.5">
                <.link
                  :if={web_url?(result.url)}
                  href={result.url}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  class="font-medium break-all text-on-app underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:decoration-accent"
                >
                  {HostName.to_unicode(result.domain)}
                </.link>
                <span :if={not web_url?(result.url)} class="font-medium break-all">{HostName.to_unicode(
                  result.domain
                )}</span>
                <span :if={result.title} class="text-xs break-words text-on-app-muted">{result.title}</span>
              </span>
              <span :if={result.page_type_name} data-part="page-type" class="text-xs text-on-app-2">
                {result.page_type_name}
              </span>
            </li>
          </ol>
        </details>
      </div>

      <dl
        id="page-type-legend"
        class="m-0 grid grid-cols-[repeat(auto-fit,minmax(min(220px,100%),1fr))] gap-x-5 gap-y-2 text-xs leading-normal"
      >
        <div
          :for={entry <- page_type_legend(@detail.first_pages)}
          id={"page-type-#{entry.page_type}"}
          class="flex flex-col gap-0.5"
        >
          <dt class="font-medium text-on-app-2">{entry.name}</dt>
          <dd class="m-0 text-on-app-muted">{entry.meaning}</dd>
          <dd :if={entry.sites != []} data-part="sites" class="m-0 mt-1 flex flex-col gap-0.5">
            <span :for={site <- entry.sites} data-part="site" class="break-all text-on-app-2">
              <.link
                :if={web_url?(site.url)}
                href={site.url}
                target="_blank"
                rel="noopener noreferrer nofollow"
                class="text-on-app underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:decoration-accent"
              >
                {HostName.to_unicode(site.domain)}
              </.link>
              <span :if={not web_url?(site.url)}>{HostName.to_unicode(site.domain)}</span>
              <span :if={site.count > 1} class="font-mono text-[11px] text-on-app-muted">
                ×{site.count}
              </span>
            </span>
          </dd>
        </div>
      </dl>

      <.competitor_prices
        price_check={@price_check}
        competitor_page_count={@competitor_page_count}
        existing_site?={@run.mode == :existing_site}
      />

      <PageComparison.table :if={@page_comparison} comparison={@page_comparison} />

      <.run_stopped_note
        :if={not @choosable?}
        id="results-run-stopped"
        link_id="results-resume-link"
        run={@run}
      >
        The research is stopped. Resume it to choose a topic.
      </.run_stopped_note>

      <p
        :if={is_nil(@page) and @choosable?}
        id="niche-next-step"
        class="m-0 mt-auto text-sm leading-normal text-on-app-muted"
      >
        Once you choose, I'll write a brief: the plan and the text for one page about this topic, with its title, headings, sections and the searches it should cover. You read it, fix it and hand it to whoever builds your site.
      </p>

      <div class={["flex flex-wrap gap-2.5", (@page || not @choosable?) && "mt-auto"]}>
        <.button
          :if={@page}
          id="open-page"
          variant="lime"
          size="large"
          navigate={RunDisplay.page_path(@page)}
        >
          Open brief
        </.button>
        <.button
          :if={is_nil(@page) and @choosable?}
          id="choose-niche"
          variant="lime"
          size="large"
          phx-click="choose"
          phx-disable-with="Choosing…"
        >
          Choose this topic and write its brief
        </.button>
        <.button
          :if={@phrase_total > niche_phrases_preview() and not @show_all_niche_phrases}
          id="all-phrases"
          variant="outline"
          size="large"
          phx-click="show_all_niche_phrases"
        >
          All {@phrase_total} {@phrase_noun}
        </.button>
        <.button
          :if={@choosable? and @selected.niche.status == :proposed}
          id="reject-niche"
          variant="ghost"
          size="large"
          phx-click="reject"
          phx-disable-with="Rejecting…"
        >
          Reject this topic
        </.button>
      </div>
    </article>
    """
  end

  attr :price_check, PriceCheck, default: nil
  attr :competitor_page_count, :integer, required: true
  attr :existing_site?, :boolean, required: true

  defp competitor_prices(assigns) do
    ~H"""
    <section id="competitor-prices" class="flex flex-col gap-2.5">
      <h3 class="m-0 font-mono text-[11px] font-normal uppercase tracking-[0.08em] text-on-app-muted">
        Competitor prices
      </h3>
      <p
        :if={is_nil(@price_check) and @competitor_page_count == 0}
        id="competitor-prices-none"
        class="m-0 text-sm leading-normal text-on-app-muted"
      >
        No business like yours is on Google's first page for these searches, so I have no prices to check.
      </p>
      <p
        :if={@price_check && @price_check.status == :failed}
        id="competitor-prices-error"
        class="m-0 text-sm leading-normal text-warn"
      >
        I couldn't check the prices: {@price_check.error}
      </p>
      <div
        :if={startable?(@price_check, @competitor_page_count)}
        class="flex flex-col items-start gap-2.5"
      >
        <p
          :if={not @existing_site?}
          id="check-prices-note"
          class="m-0 text-sm leading-normal text-on-app-muted"
        >
          I'll open the pages of up to {PriceChecks.page_limit()} businesses like yours from Google's first page and copy the prices they state; reading each page is one AI request, added to this research's API cost.
        </p>
        <p
          :if={@existing_site?}
          id="check-prices-note"
          class="m-0 text-sm leading-normal text-on-app-muted"
        >
          I'll open the pages of up to {PriceChecks.page_limit()} businesses like yours from Google's first page, copy the prices they state and compare their pages with yours; reading each page is one AI request, and counting the sites that link to them is one more request, added to this research's API cost.
        </p>
        <.button
          id="check-prices"
          variant="outline"
          size="large"
          phx-click="check_prices"
          phx-disable-with="Starting…"
        >
          {if(@existing_site?,
            do: "Check competitor prices and pages",
            else: "Check competitor prices"
          )}
        </.button>
      </div>
      <p
        :if={@price_check && @price_check.status == :checking}
        id="competitor-prices-status"
        role="status"
        class="m-0 text-sm leading-normal text-on-app-2"
      >
        I'm reading competitor pages and looking for prices: {pages_read_line(@price_check)} done.
      </p>
      <p
        :if={@price_check && @price_check.status == :done}
        id="competitor-prices-source"
        class="m-0 text-xs leading-normal text-on-app-muted"
      >
        I copy prices exactly as the pages write them. I checked each one against the page text.
      </p>
      <ul
        :if={@price_check && @price_check.status == :done}
        id="competitor-prices-list"
        class="m-0 flex list-none flex-col p-0 rounded-tile border border-app-line-strong bg-app-raised"
      >
        <li
          :for={page <- @price_check.competitor_pages}
          id={"competitor-page-#{page.id}"}
          data-outcome={page.outcome}
          class="flex flex-col gap-1 border-t border-app-line-strong px-4 py-3 text-sm first:border-t-0"
        >
          <.link
            :if={web_url?(page.read_url || page.url)}
            href={page.read_url || page.url}
            target="_blank"
            rel="noopener noreferrer"
            data-part="domain"
            class="font-medium break-all text-on-app underline decoration-app-line-strong underline-offset-2 transition-colors duration-150 hover:decoration-accent"
          >
            {HostName.to_unicode(page.domain)}
          </.link>
          <span
            :if={not web_url?(page.read_url || page.url)}
            data-part="domain"
            class="font-medium break-all"
          >
            {HostName.to_unicode(page.domain)}
          </span>
          <ul :if={page.outcome == :prices_found} class="m-0 flex list-none flex-col gap-0.5 p-0">
            <li :for={offer <- page.offers} data-part="offer" class="break-words text-on-app-2">
              {offer.name}: <span class="font-mono whitespace-nowrap text-on-app">{offer.price}</span>
            </li>
          </ul>
          <span :if={page.outcome == :no_prices} data-part="no-prices" class="text-on-app-muted">
            I found no prices on this page
          </span>
          <span :if={page.outcome == :unreadable} data-part="unreadable" class="text-on-app-muted">
            This page could not be opened
          </span>
        </li>
      </ul>
    </section>
    """
  end

  defp load_results(socket) do
    %{run: run, requested: requested, show_low_niches: show_low_niches} = socket.assigns
    ready? = Run.results_ready?(run)
    summaries = Niches.list_summaries(run)
    offered = Enum.filter(summaries, &Niche.choosable?(&1.niche))
    {worth, low} = Enum.split_with(offered, &Scoring.worth?(&1.niche.score))
    selected = if ready?, do: select_niche(offered, requested.niche_id)
    show_low_niches = show_low_niches or Enum.member?(low, selected)
    view = if ready?, do: requested.view, else: :phrases
    phrase_counts = Phrases.count_by_status(run)
    short_description = RunDisplay.short_description(run.description)
    listed_niches = if show_low_niches, do: offered, else: worth
    niche_names = niche_names(summaries)
    site_pages = site_pages(run)

    socket
    |> assign(
      page_title: "Results · #{short_description}",
      ready?: ready?,
      choosable?: Run.choosable?(run),
      view: view,
      short_description: short_description,
      context_line: RunDisplay.context_line(run),
      headline: headline_text(%{ready?: ready?, offered: offered, worth: worth}),
      status_line: status_line(%{run: run, ready?: ready?, offered: offered}),
      counts: %{niches: length(offered), kept: phrase_counts.kept, rejected: phrase_counts.rejected},
      offered_ids: Enum.map(offered, & &1.niche.id),
      selected: selected,
      selected_id: selected && selected.niche.id,
      low_count: length(low),
      show_low_niches: show_low_niches,
      list_limit: @list_limit,
      site_pages: site_pages
    )
    |> stream_niches(%{view: view, niches: listed_niches, selected: selected, site_pages: site_pages})
    |> stream_phrases(%{view: view, names: niche_names})
    |> assign_detail()
  end

  defp stream_niches(socket, %{view: :niches, niches: niches, selected: selected, site_pages: site_pages}) do
    run = socket.assigns.run
    rows = Enum.map(niches, &niche_row(&1, %{run: run, selected: selected, site_pages: site_pages}))
    stream(socket, :niches, rows, reset: true)
  end

  defp stream_niches(socket, _other_view), do: stream(socket, :niches, [], reset: true)

  defp stream_phrases(socket, %{view: :phrases, names: names}) do
    rows =
      socket.assigns.run
      |> Phrases.list_for_run(%{status: :kept, limit: @list_limit})
      |> Enum.map(&kept_phrase_row(&1, %{names: names, mode: socket.assigns.run.mode}))

    socket
    |> stream(:phrases, rows, reset: true)
    |> stream(:rejected_phrases, [], reset: true)
  end

  defp stream_phrases(socket, %{view: :rejected}) do
    rows =
      socket.assigns.run
      |> Phrases.list_for_run(%{status: :rejected, limit: @list_limit})
      |> Enum.map(&rejected_phrase_row/1)

    socket
    |> stream(:phrases, [], reset: true)
    |> stream(:rejected_phrases, rows, reset: true)
  end

  defp stream_phrases(socket, _niches_view) do
    socket
    |> stream(:phrases, [], reset: true)
    |> stream(:rejected_phrases, [], reset: true)
  end

  defp assign_detail(%{assigns: %{selected: nil}} = socket) do
    socket
    |> assign(detail: nil, price_check: nil, competitor_page_count: 0, page_comparison: nil)
    |> stream(:niche_phrases, [], reset: true)
  end

  defp assign_detail(%{assigns: %{run: run, selected: %{niche: niche}}} = socket) do
    detail = Niches.niche_detail(run, niche)

    shown_phrases =
      if socket.assigns.show_all_niche_phrases,
        do: detail.phrases,
        else: Enum.take(detail.phrases, @niche_phrases_preview)

    results_by_phrase = Map.new(detail.first_pages, &{&1.id, &1.results})
    rows = Enum.map(shown_phrases, &niche_phrase_row(&1, Map.get(results_by_phrase, &1.id, [])))

    price_check = PriceChecks.get_for_niche(niche)

    socket
    |> assign(
      detail: detail,
      price_check: price_check,
      competitor_page_count: length(PriceChecks.competitor_pages(detail.first_pages)),
      page_comparison: page_comparison(%{run: run, niche: niche, price_check: price_check})
    )
    |> stream(:niche_phrases, rows, reset: true)
  end

  defp headline_text(%{ready?: false}), do: ResultsHeadline.text(:before_scoring)

  defp headline_text(%{offered: offered, worth: worth}) do
    niche_count = length(offered)
    worth_count = length(worth)
    ResultsHeadline.text(%{niches: niche_count, worth: worth_count})
  end

  defp status_line(%{ready?: false, run: run}), do: StatusLine.sentence(%{run: run, progress: nil})
  defp status_line(%{offered: []}), do: ResultsHeadline.status_line(nil)

  defp status_line(%{offered: [best | _other_niches]}) do
    ResultsHeadline.status_line(%{name: best.niche.name, competition: best.competition})
  end

  defp select_niche([], _requested_niche_id), do: nil

  defp select_niche([top | _other_niches] = offered, requested_niche_id) do
    Enum.find(offered, top, &(&1.niche.id == requested_niche_id))
  end

  defp next_niche_id(offered_ids, rejected_id) do
    index = Enum.find_index(offered_ids, &(&1 == rejected_id))
    remaining = List.delete(offered_ids, rejected_id)
    Enum.at(remaining, index) || List.last(remaining)
  end

  defp niche_row(%{niche: niche} = summary, %{run: run, selected: selected, site_pages: site_pages}) do
    advice = NicheAdvice.advice(summary)

    %{
      id: niche.id,
      name: niche.name,
      advice: advice.label,
      advice_class: advice.class,
      figures: NicheAdvice.figures(summary),
      selected?: selected != nil and selected.niche.id == niche.id,
      path: view_path(run, %{view: "niches", niche: niche.id}),
      site_page: site_page(site_pages, niche.id)
    }
  end

  defp subscribe(run) do
    Research.subscribe(run)
    PriceChecks.subscribe(run)
    if run.mode == :existing_site, do: SiteScans.subscribe(run)
  end

  defp page_comparison(%{run: %Run{mode: :existing_site} = run, niche: niche, price_check: %PriceCheck{} = price_check}),
    do: PageComparison.build(%{run: run, price_check: price_check, site: SiteScans.niche_comparison(run, niche.id)})

  defp page_comparison(%{run: run}), do: PageComparison.build(%{run: run})

  defp site_pages(%Run{mode: :existing_site} = run), do: SiteScans.matched_pages_by_niche(run)
  defp site_pages(%Run{}), do: nil

  defp site_page(nil, _niche_id), do: :unknown

  defp site_page(site_pages, niche_id) do
    case Map.get(site_pages, niche_id) do
      [address | _more] -> address
      nil -> nil
    end
  end

  defp kept_phrase_row(run_phrase, %{names: names, mode: mode}) do
    %{
      id: run_phrase.id,
      phrase: run_phrase.phrase.phrase,
      figures:
        "typed #{volume_or_missing(run_phrase.metrics)} times a month · ad click price #{cpc_or_missing(run_phrase.metrics)}" <>
          position_figure(mode, run_phrase.current_position),
      quick_win?: Phrases.quick_win?(run_phrase.current_position),
      note: need_note(Map.get(names, run_phrase.cluster_id))
    }
  end

  defp rejected_phrase_row(run_phrase) do
    %{
      id: run_phrase.id,
      phrase: run_phrase.phrase.phrase,
      figures: "typed #{volume_or_missing(run_phrase.metrics)} times a month",
      quick_win?: false,
      note: run_phrase.rejection_reason
    }
  end

  defp niche_phrase_row(phrase, first_page_results) do
    domains = Enum.map(first_page_results, & &1.domain)

    %{
      sites: Enum.take(domains, @sites_in_row),
      more_sites: max(length(domains) - @sites_in_row, 0),
      id: phrase.id,
      phrase: phrase.phrase,
      volume: integer_or_missing(phrase.volume),
      city_volume: integer_or_missing(phrase.city_volume),
      cpc: money_or_missing(phrase.cpc, phrase.currency),
      holders: phrase.holders || @missing,
      position: position_or_missing(phrase.current_position),
      quick_win?: phrase.quick_win?
    }
  end

  defp niche_names(summaries), do: Map.new(summaries, &{&1.niche.id, &1.niche.name})

  defp need_note(nil), do: nil
  defp need_note(niche_name), do: "Topic: #{niche_name}"

  defp view_path(run, %{view: view, niche: nil}), do: ~p"/app/runs/#{run}/results?#{[view: view]}"
  defp view_path(run, %{view: view, niche: niche_id}), do: ~p"/app/runs/#{run}/results?#{[view: view, niche: niche_id]}"

  defp requested_view(%{"view" => "phrases"}), do: :phrases
  defp requested_view(%{"view" => "rejected"}), do: :rejected
  defp requested_view(_niches_or_unknown), do: :niches

  defp requested_niche_id(%{"niche" => niche_param}) when is_binary(niche_param) do
    case Integer.parse(niche_param) do
      {niche_id, ""} -> niche_id
      _malformed -> nil
    end
  end

  defp requested_niche_id(_missing), do: nil

  defp open_page(%Page{status: :failed}), do: nil
  defp open_page(page), do: page

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, @not_found_message)
    |> push_navigate(to: ~p"/app/runs")
  end

  defp score_label(nil), do: "not rated"

  defp score_label(%Decimal{} = score) do
    rounded = score |> Decimal.round(0) |> Decimal.to_integer()
    "rating #{rounded} out of 10"
  end

  defp low_niches_label(count) do
    worth_threshold = Scoring.worth_threshold()
    threshold = Decimal.to_string(worth_threshold, :normal)
    "#{Format.plural(count, @niche_forms)} rated below #{threshold} out of 10"
  end

  defp volume_or_missing(nil), do: @missing
  defp volume_or_missing(metrics), do: integer_or_missing(metrics.search_volume)

  defp cpc_or_missing(nil), do: @missing
  defp cpc_or_missing(metrics), do: money_or_missing(metrics.cpc, metrics.currency)

  defp integer_or_missing(nil), do: @missing
  defp integer_or_missing(number), do: Format.integer(number)

  defp money_or_missing(nil, _currency), do: @missing
  defp money_or_missing(amount, currency), do: Format.money(amount, currency)

  defp usd_or_missing(nil), do: @missing
  defp usd_or_missing(amount), do: Format.usd(amount)

  defp competitors_or_missing(nil), do: @missing
  defp competitors_or_missing(count), do: "#{count} of #{@serp_size}"

  defp position_figure(:existing_site, position), do: " · your site's position #{position_or_missing(position)}"
  defp position_figure(_mode, _position), do: ""

  defp quick_win_noun(count), do: Format.plural(count, @quick_win_forms)

  defp position_or_missing(nil), do: @missing
  defp position_or_missing(position), do: Format.decimal(position, 1)

  defp niche_phrases_preview, do: @niche_phrases_preview

  defp result_count(results), do: "#{length(results)} #{Format.plural(length(results), @result_forms)}"

  defp startable?(nil, competitor_page_count), do: competitor_page_count > 0
  defp startable?(%PriceCheck{status: status}, _competitor_page_count), do: status == :failed

  defp pages_read_line(%PriceCheck{competitor_pages: pages}) do
    read = Enum.count(pages, &(&1.outcome != :waiting))
    "#{read} of #{length(pages)} #{Format.plural(length(pages), @page_forms)}"
  end

  defp web_url?("http://" <> _rest), do: true
  defp web_url?("https://" <> _rest), do: true
  defp web_url?(_other), do: false

  # The five Page Types, what each means and the sites of that type found on
  # the first pages of the Niche's checked Phrases, the most frequent first.
  defp page_type_legend(first_pages) do
    plurals = SerpAssessment.page_type_plurals()
    results_by_page_type = first_pages |> Enum.flat_map(& &1.results) |> Enum.group_by(& &1.page_type)

    Enum.map(@page_type_meanings, fn {page_type, meaning} ->
      %{
        page_type: page_type,
        name: Map.fetch!(plurals, page_type),
        meaning: meaning,
        sites: results_by_page_type |> Map.get(page_type, []) |> sites()
      }
    end)
  end

  defp sites(results) do
    results
    |> Enum.group_by(& &1.domain)
    |> Enum.map(fn {domain, [first | _rest] = of_domain} ->
      %{domain: domain, url: first.url, count: length(of_domain)}
    end)
    |> Enum.sort_by(&{-&1.count, &1.domain})
  end
end
