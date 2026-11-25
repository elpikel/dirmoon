defmodule DirmoonWeb.PagesLive do
  @moduledoc """
  The briefs list, "Briefs" (`/app/pages`): the Account's Pages, each
  holding one Niche's Brief, newest first, each with its title, Niche, Mode,
  status and date, linking to its brief screen. With none it invites the User
  to pick a Niche in the results. Same look as the runs list (`RunsLive`): rows
  filling the app shell's working area.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Format
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.StatusLine
  alias DirmoonWeb.PageDisplay
  alias DirmoonWeb.RunDisplay

  @brief_forms %{one: "brief", other: "briefs"}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:pages}
      context="briefs"
      note={@count_note}
    >
      <:status><span id="pages-status-line">{@status_line}</span></:status>
      <section id="pages-screen" class="flex grow flex-col">
        <h1 class="sr-only">Briefs</h1>
        <ul id="pages" phx-update="stream" class="m-0 flex list-none flex-col p-0">
          <li id="pages-empty" class="hidden px-5 py-12 only:block">
            <div class="flex flex-col items-center gap-4 text-center">
              <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
                Your briefs will show up here.
              </span>
              <p class="m-0 max-w-[460px] text-[15px] leading-normal text-on-app-2">
                Choose a niche in the research results and I'll write a brief for it.
              </p>
              <.button id="go-to-results" variant="lime" size="large" navigate={~p"/app/runs"}>
                Go to results <.icon name="hero-arrow-right" class="size-[18px]" />
              </.button>
            </div>
          </li>
          <li
            :for={{dom_id, row} <- @streams.pages}
            id={dom_id}
            data-status={row.status}
            class="border-b border-app-line last:border-b-0"
          >
            <.link
              navigate={row.path}
              class="flex min-h-target-min flex-wrap items-center gap-x-6 gap-y-2.5 px-5 py-4 text-on-app no-underline transition-colors duration-150 hover:bg-app-raised focus-visible:bg-app-raised focus-visible:outline-none"
            >
              <span class="flex min-w-0 flex-[1_1_320px] flex-col gap-1">
                <span id={"#{dom_id}-title"} class="text-[15px] font-semibold">{row.title}</span>
                <span class="text-[13px] text-on-app-2">
                  <span id={"#{dom_id}-niche"}>{row.niche}</span>
                  · <span id={"#{dom_id}-mode"}>{row.mode}</span>
                </span>
              </span>
              <span class="flex flex-wrap items-center gap-x-5 gap-y-1.5 font-mono text-[11px] text-on-app-muted">
                <.page_status id={"#{dom_id}-status"} status={row.status} label={row.status_label} />
                <span id={"#{dom_id}-date"}>{row.date}</span>
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
    pages = Pages.list_pages(socket.assigns.current_scope)
    rows = Enum.map(pages, &row/1)

    {:ok,
     socket
     |> assign(
       page_title: "Briefs",
       status_line: StatusLine.list_sentence(pages),
       count_note: count_note(pages)
     )
     |> stream(:pages, rows)}
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp page_status(%{status: :failed} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-warn">
      <.icon name="hero-exclamation-triangle" class="size-[13px]" />{@label}
    </span>
    """
  end

  defp page_status(assigns) do
    ~H"""
    <span
      id={@id}
      class="rounded-pill border border-app-line-strong px-[9px] py-[3px] text-on-app"
    >
      {@label}
    </span>
    """
  end

  defp row(%Page{} = page) do
    %{
      id: page.id,
      title: PageDisplay.title(page),
      niche: page.niche.name,
      mode: RunDisplay.mode_label(page.run.mode),
      status: page.status,
      status_label: PageDisplay.status_label(page.status),
      date: PageDisplay.date(page),
      path: RunDisplay.page_path(page)
    }
  end

  defp count_note(pages) do
    count = length(pages)
    "#{count} #{Format.plural(count, @brief_forms)}"
  end
end
