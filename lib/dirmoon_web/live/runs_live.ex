defmodule DirmoonWeb.RunsLive do
  @moduledoc """
  The runs list, "Wyniki" (`/app/runs`): the Account's Research Runs, newest
  first, each with its description, Mode, location, status, date and API
  Cost, linking to the run or, once its results are ready
  (`Run.results_ready?/1`), to them. With
  no runs it invites the User to start one. Same look as the other screens
  (`docs/design/README.md` sections 8.1–8.2): hero and one dark panel.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Polish
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunsStatusLine
  alias DirmoonWeb.RunDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:runs}>
      <section id="runs-screen" class="flex flex-col items-center gap-6 text-center">
        <.eyebrow>Wyniki</.eyebrow>
        <.headline id="runs-headline">
          Twoje
          <:underline>researche.</:underline>
        </.headline>
        <p class="m-0 max-w-[620px] text-[clamp(16px,1.4vw,18px)] leading-normal text-pretty text-body">
          Każdy opis biznesu, który sprawdziłem, z jego stanem i kosztem API.
        </p>

        <.dark_panel id="runs-panel" context="wyniki" note={@count_note} class="mt-5">
          <:status><span id="runs-status-line">{@status_line}</span></:status>
          <ul id="runs" phx-update="stream" class="m-0 flex list-none flex-col p-0">
            <li id="runs-empty" class="hidden px-5 py-12 only:block">
              <div class="flex flex-col items-center gap-4 text-center">
                <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
                  Tu pojawią się Twoje researche.
                </span>
                <p class="m-0 max-w-[460px] text-[15px] leading-normal text-on-slate-2">
                  Opisz biznes albo pomysł, a sprawdzę, czego ludzie szukają i które nisze warto zająć.
                </p>
                <.button
                  id="start-first-research"
                  variant="lime"
                  size="large"
                  navigate={~p"/app/research/new"}
                >
                  Zacznij pierwszy research <.icon name="hero-arrow-right" class="size-[18px]" />
                </.button>
              </div>
            </li>
            <li
              :for={{dom_id, row} <- @streams.runs}
              id={dom_id}
              data-status={row.status}
              class="border-b border-slate-line last:border-b-0"
            >
              <.link
                navigate={row.path}
                class="flex min-h-target-min flex-wrap items-center gap-x-6 gap-y-2.5 px-5 py-4 text-on-slate no-underline transition-colors duration-150 hover:bg-slate-raised focus-visible:bg-slate-raised focus-visible:outline-none"
              >
                <span class="flex min-w-0 flex-[1_1_320px] flex-col gap-1">
                  <span class="text-[15px] font-semibold">{row.short_description}</span>
                  <span class="text-[13px] text-on-slate-2">
                    {row.mode}<span :if={row.domain}> · {row.domain}</span> · {row.location}
                  </span>
                </span>
                <span class="flex flex-wrap items-center gap-x-5 gap-y-1.5 font-mono text-[11px] text-on-slate-muted">
                  <.run_status id={"#{dom_id}-status"} status={row.status} label={row.status_label} />
                  <span>{row.date}</span>
                  <span id={"#{dom_id}-cost"}>Koszt API: {row.cost}</span>
                </span>
                <.icon
                  name="hero-chevron-right-mini"
                  class="size-4 flex-none text-on-slate-muted max-sm:hidden"
                />
              </.link>
            </li>
          </ul>
        </.dark_panel>
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
       page_title: "Wyniki",
       status_line: RunsStatusLine.sentence(runs),
       count_note: RunsStatusLine.count(runs)
     )
     |> stream(:runs, rows)}
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp run_status(%{status: :done} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-accent">
      <.icon name="hero-check-mini" class="size-[13px]" />{@label}
    </span>
    """
  end

  defp run_status(%{status: :failed} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-warn">
      <.icon name="hero-exclamation-triangle" class="size-[13px]" />{@label}
    </span>
    """
  end

  defp run_status(%{status: :stopped} = assigns) do
    ~H"""
    <span id={@id} class="text-on-slate-muted">{@label}</span>
    """
  end

  defp run_status(assigns) do
    ~H"""
    <span
      id={@id}
      class="rounded-pill border border-slate-line-strong px-[9px] py-[3px] text-on-slate"
    >
      {@label}
    </span>
    """
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
      cost: Polish.usd(cost),
      path: RunDisplay.path(run)
    }
  end

  defp site_domain(%Run{mode: :existing_site, domain: domain}), do: domain
  defp site_domain(_new_idea_run), do: nil
end
