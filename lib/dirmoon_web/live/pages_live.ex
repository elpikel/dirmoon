defmodule DirmoonWeb.PagesLive do
  @moduledoc """
  The pages list, "Strony" (`/app/pages`): the Account's Produced Pages,
  newest first, each with its title, Niche, Mode, status, published URL and
  date, linking to its page screen. With no pages it invites the User to pick
  a Niche in the results. Same look as the runs list (`RunsLive`): hero and
  one dark panel.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.StatusLine
  alias Dirmoon.Polish
  alias DirmoonWeb.PageDisplay
  alias DirmoonWeb.RunDisplay

  @page_forms %{one: "strona", few: "strony", many: "stron"}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:pages}>
      <section id="pages-screen" class="flex flex-col items-center gap-6 text-center">
        <.eyebrow>Strony</.eyebrow>
        <.headline id="pages-headline">
          Twoje
          <:underline>strony.</:underline>
        </.headline>
        <p class="m-0 max-w-[620px] text-[clamp(16px,1.4vw,18px)] leading-normal text-pretty text-body">
          Każda nisza, którą wybrałeś, z briefem, stanem strony i adresem po publikacji.
        </p>

        <.dark_panel id="pages-panel" context="strony" note={@count_note} class="mt-5">
          <:status><span id="pages-status-line">{@status_line}</span></:status>
          <ul id="pages" phx-update="stream" class="m-0 flex list-none flex-col p-0">
            <li id="pages-empty" class="hidden px-5 py-12 only:block">
              <div class="flex flex-col items-center gap-4 text-center">
                <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
                  Tu pojawią się Twoje strony.
                </span>
                <p class="m-0 max-w-[460px] text-[15px] leading-normal text-on-slate-2">
                  Wybierz niszę w wynikach researchu, a napiszę dla niej brief i stronę.
                </p>
                <.button id="go-to-results" variant="lime" size="large" navigate={~p"/app/runs"}>
                  Przejdź do wyników <.icon name="hero-arrow-right" class="size-[18px]" />
                </.button>
              </div>
            </li>
            <li
              :for={{dom_id, row} <- @streams.pages}
              id={dom_id}
              data-status={row.status}
              class="border-b border-slate-line last:border-b-0"
            >
              <.link
                navigate={row.path}
                class="flex min-h-target-min flex-wrap items-center gap-x-6 gap-y-2.5 px-5 py-4 text-on-slate no-underline transition-colors duration-150 hover:bg-slate-raised focus-visible:bg-slate-raised focus-visible:outline-none"
              >
                <span class="flex min-w-0 flex-[1_1_320px] flex-col gap-1">
                  <span id={"#{dom_id}-title"} class="text-[15px] font-semibold">{row.title}</span>
                  <span class="text-[13px] text-on-slate-2">
                    <span id={"#{dom_id}-niche"}>{row.niche}</span>
                    · <span id={"#{dom_id}-mode"}>{row.mode}</span>
                  </span>
                  <span
                    :if={row.published_url}
                    id={"#{dom_id}-url"}
                    class="font-mono text-xs break-all text-accent"
                  >
                    {row.published_url}
                  </span>
                </span>
                <span class="flex flex-wrap items-center gap-x-5 gap-y-1.5 font-mono text-[11px] text-on-slate-muted">
                  <.page_status id={"#{dom_id}-status"} status={row.status} label={row.status_label} />
                  <span id={"#{dom_id}-date"}>{row.date}</span>
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
    pages = Pages.list_pages(socket.assigns.current_scope)
    rows = Enum.map(pages, &row/1)

    {:ok,
     socket
     |> assign(
       page_title: "Strony",
       status_line: StatusLine.list_sentence(pages),
       count_note: count_note(pages)
     )
     |> stream(:pages, rows)}
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp page_status(%{status: :published} = assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-1.5 text-accent">
      <.icon name="hero-check-mini" class="size-[13px]" />{@label}
    </span>
    """
  end

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
      class="rounded-pill border border-slate-line-strong px-[9px] py-[3px] text-on-slate"
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
      published_url: page.published_url,
      date: PageDisplay.date(page),
      path: RunDisplay.page_path(page)
    }
  end

  defp count_note(pages) do
    count = length(pages)
    "#{count} #{Polish.plural(count, @page_forms)}"
  end
end
