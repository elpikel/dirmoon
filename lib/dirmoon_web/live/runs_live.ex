defmodule DirmoonWeb.RunsLive do
  @moduledoc """
  The runs list, "Results" (`/app/runs`): the Account's Research Runs, newest
  first, each with its description, Mode, location, status, date and API
  Cost, linking to the run or, once its results are ready
  (`Run.results_ready?/1`), to them. With
  no runs it invites the User to start one. The rows fill the app shell's
  working area.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Format
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunsStatusLine
  alias Dirmoon.WebPage.HostName
  alias DirmoonWeb.RunDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:runs}
      context="results"
      note={@count_note}
    >
      <:status><span id="runs-status-line">{@status_line}</span></:status>
      <section id="runs-screen" class="flex grow flex-col">
        <h1 class="sr-only">Results</h1>
        <ul id="runs" phx-update="stream" class="m-0 flex list-none flex-col p-0">
          <li id="runs-empty" class="hidden px-5 py-12 only:block">
            <div class="flex flex-col items-center gap-4 text-center">
              <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
                Your research runs will show up here.
              </span>
              <p class="m-0 max-w-[460px] text-[15px] leading-normal text-on-app-2">
                Describe a business or an idea and I'll check what people search for on Google and which topics are worth going after.
              </p>
              <.button
                id="start-first-research"
                variant="lime"
                size="large"
                navigate={~p"/app/research/new"}
              >
                Start your first research <.icon name="hero-arrow-right" class="size-[18px]" />
              </.button>
            </div>
          </li>
          <li
            :for={{dom_id, row} <- @streams.runs}
            id={dom_id}
            data-status={row.status}
            class="border-b border-app-line last:border-b-0"
          >
            <.link
              navigate={row.path}
              class="flex min-h-target-min flex-wrap items-center gap-x-6 gap-y-2.5 px-5 py-4 text-on-app no-underline transition-colors duration-150 hover:bg-app-raised focus-visible:bg-app-raised focus-visible:outline-none"
            >
              <span class="flex min-w-0 flex-[1_1_320px] flex-col gap-1">
                <span class="text-[15px] font-semibold">{row.short_description}</span>
                <span class="text-[13px] text-on-app-2">
                  {row.mode}<span :if={row.domain}> · {row.domain}</span> · {row.location}
                </span>
              </span>
              <span class="flex flex-wrap items-center gap-x-5 gap-y-1.5 font-mono text-[11px] text-on-app-muted">
                <.run_status id={"#{dom_id}-status"} status={row.status} label={row.status_label} />
                <span>{row.date}</span>
                <span id={"#{dom_id}-cost"}>API cost: {row.cost}</span>
              </span>
              <.icon
                name="hero-chevron-right-mini"
                class="size-4 flex-none text-on-app-muted max-sm:hidden"
              />
            </.link>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    runs = Research.list_runs(socket.assigns.current_scope)
    costs = Research.run_costs(runs)
    rows = Enum.map(runs, &row(&1, costs))

    {:ok,
     socket
     |> assign(
       page_title: "Results",
       status_line: RunsStatusLine.sentence(runs),
       count_note: RunsStatusLine.count(runs)
     )
     |> stream(:runs, rows)}
  end

  defp row(%Run{id: run_id} = run, costs) do
    cost = Map.fetch!(costs, run_id)

    %{
      id: run.id,
      short_description: RunDisplay.short_description(run.description),
      mode: RunDisplay.mode_label(run.mode),
      domain: site_domain(run),
      location: RunDisplay.location(run),
      status: run.status,
      status_label: RunDisplay.status_label(run.status),
      date: RunDisplay.date(run),
      cost: Format.usd(cost),
      path: RunDisplay.path(run)
    }
  end

  defp site_domain(%Run{mode: :existing_site, domain: domain}), do: HostName.to_unicode(domain)
  defp site_domain(_new_idea_run), do: nil
end
