defmodule DirmoonWeb.Layouts do
  @moduledoc """
  The embedded root template plus the app, landing and auth layouts, and the
  flash group they render. The landing and auth layouts sit on the dotted
  page background (`page-dots`) from `docs/design/README.md` section 8.2; the
  signed-in app is a full-screen dark shell in the neutral gray app tokens
  (owner's decisions, see `docs/MEMORY.md`).
  """
  use DirmoonWeb, :html

  embed_templates "layouts/*"

  @doc """
  Mounts a LiveView that renders in the dark app shell: the root layout then
  paints the `<body>` in the app's working-area gray, so scrolling past the
  shell's edge never shows the light page. Other pages keep the light page
  background.

      live_session :app, on_mount: [{DirmoonWeb.Layouts, :app_body}] do
  """
  def on_mount(:app_body, _params, _session, socket) do
    {:cont, assign(socket, :body_surface, "app")}
  end

  @doc """
  Renders the signed-in app shell: one dark gray tool filling the window.
  The chrome (top bar and sidebar) is the darkest gray, the working area one
  step lighter and the status row lighter again.
  A slim top bar (the moon mark, "dirmoon / <context>" in mono, and the
  user's email with "Settings" and "Log out"), a sidebar ("New research",
  "Results", "Briefs"), the status row (moon mark, the screen's first-person
  sentence and its note) and the screen's working area. On phones (below
  860px) the sidebar becomes a row of links under the top bar and the email
  is only read out to screen readers. The light dotted page, the nav card,
  eyebrows and headlines belong to the landing and sign-in layouts only.

      <Layouts.app flash={@flash} current_scope={@current_scope} active={:runs} context="results">
        <:status>You have 3 research runs.</:status>
        <div id="runs">...</div>
      </Layouts.app>

  `active` marks its sidebar link with `aria-current="page"`. `demo_services`
  lists the services answered with Demo Data in the "TEST DATA" strip above
  the top bar; it defaults to `Dirmoon.demo_services/0`, and an empty list
  hides the strip.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom,
    default: nil,
    values: [nil, :new_research, :runs, :pages],
    doc: "the sidebar link of the page being shown"

  attr :context, :string, required: true, doc: "shown as `dirmoon / <context>` in the top bar"
  attr :note, :string, default: nil, doc: "short mono note at the right of the status row"

  attr :demo_services, :list,
    doc: "names of the services answered by demo adapters; defaults to `Dirmoon.demo_services/0`"

  slot :status, doc: "one first-person sentence saying what the tool found or is doing"
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:sidebar_links, app_sidebar_links())
      |> assign_new(:demo_services, &Dirmoon.demo_services/0)

    ~H"""
    <div
      data-layout="app"
      data-surface="dark"
      class="flex min-h-screen flex-col bg-app font-sans text-on-app"
    >
      <.demo_data_banner :if={@demo_services != []} services={@demo_services} />
      <header
        id="app-top-bar"
        class="flex flex-wrap items-center justify-between gap-x-5 border-b border-app-line bg-app-chrome px-5 max-sm:px-3"
      >
        <div class="flex min-h-target-min min-w-0 flex-1 items-center gap-2.5 font-mono text-xs text-on-app-muted">
          <.link
            href={new_research_path()}
            data-part="brand"
            aria-label="dirmoon"
            class="flex min-h-target-min flex-none items-center gap-2.5 text-on-app no-underline"
          >
            <.moon_mark tone="accent" size={16} />
            <span aria-hidden="true">dirmoon</span>
          </.link>
          <span id="app-context" class="min-w-0 truncate">/ {@context}</span>
        </div>
        <.user_menu :if={@current_scope} user={@current_scope.user} />
      </header>

      <div class="flex grow flex-col min-[860px]:flex-row">
        <nav
          id="app-nav"
          aria-label="App"
          class="flex flex-none flex-wrap gap-1.5 border-app-line bg-app-chrome px-3 py-2 min-[860px]:w-[220px] min-[860px]:flex-col min-[860px]:border-r min-[860px]:py-4 max-[859px]:border-b"
        >
          <.app_sidebar_link
            id="nav-new-research"
            href={new_research_path()}
            variant="action"
            active={@active == :new_research}
            class="min-[860px]:mb-3"
          >
            <.icon name="hero-plus-mini" class="size-4 flex-none text-accent" /> New research
          </.app_sidebar_link>
          <.app_sidebar_link
            :for={link <- @sidebar_links}
            id={"nav-#{link.page}"}
            href={link.path}
            active={link.page == @active}
          >
            {link.label}
          </.app_sidebar_link>
        </nav>

        <div class="flex min-w-0 grow flex-col">
          <div
            :if={@status != [] or @note}
            id="app-status"
            role="status"
            class="flex flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-app-line bg-app-raised px-5 py-3.5 max-sm:px-4"
          >
            <.moon_mark tone="accent" size={26} />
            <span class="min-w-0 flex-[1_1_240px] text-[15px] font-medium">{render_slot(@status)}</span>
            <span :if={@note} id="app-note" class="font-mono text-[11px] text-on-app-muted">
              {@note}
            </span>
          </div>
          <main id="app-main" class="flex min-w-0 grow flex-col">
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} placement="app" />
    """
  end

  @doc """
  Renders the signed-out landing shell: the light dotted page under a
  floating nav card, with the `nav` slot on the card's right-hand side (the
  sign-in link).

      <Layouts.landing>
        <:nav><.button variant="dark" href={~p"/users/log-in"}>Sign in</.button></:nav>
        <section id="hero">...</section>
      </Layouts.landing>
  """
  slot :nav, doc: "the right-hand side of the nav card"
  slot :inner_block, required: true

  def landing(assigns) do
    ~H"""
    <div data-layout="landing" class="page-dots flex min-h-screen flex-col font-sans text-ink">
      <header class="px-gutter-phone pt-4 sm:px-gutter">
        <.nav_card id="landing-nav">{render_slot(@nav)}</.nav_card>
      </header>
      <main class="mx-auto flex w-full max-w-content grow flex-col px-gutter-phone pt-16 pb-[88px] sm:px-gutter">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Renders the sign-in shell: the mark and wordmark above a centred white card
  on the dotted page.

      <Layouts.auth flash={@flash}>
        <h1>Sign in</h1>
      </Layouts.auth>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div
      data-layout="auth"
      class="page-dots flex min-h-screen flex-col items-center justify-center gap-8 px-gutter-phone py-16 font-sans text-ink sm:px-gutter"
    >
      <.wordmark href={~p"/"} />
      <main class="flex w-full max-w-[420px] flex-col gap-6 rounded-panel border border-line bg-white p-8 shadow-nav max-sm:p-6">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group: the info and error notices a screen set. A lost
  connection is not announced; LiveView reconnects on its own. On phones and
  tablets it sits at the bottom of the screen (full width between the side
  gutters on phones). On desktop the `page` placement (landing and sign-in)
  sits top right, below the nav card; the `app` placement stays bottom
  right, so it never covers the app's top bar or status row, and draws its
  notices in the app's grays.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"
  attr :placement, :string, default: "page", values: ~w(page app), doc: "where it sits on desktop"

  def flash_group(assigns) do
    assigns = assign(assigns, :surface, flash_surface(assigns.placement))

    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class={[
        "pointer-events-none fixed inset-x-gutter-phone bottom-4 z-50 flex flex-col gap-2 sm:left-auto sm:right-gutter sm:w-96",
        @placement == "page" && "lg:top-36 lg:bottom-auto"
      ]}
    >
      <.flash kind={:info} flash={@flash} surface={@surface} />
      <.flash kind={:error} flash={@flash} surface={@surface} />
    </div>
    """
  end

  attr :services, :list, required: true

  defp demo_data_banner(assigns) do
    ~H"""
    <div
      id="demo-data-banner"
      role="status"
      class="flex flex-wrap items-center justify-center gap-x-3 gap-y-0.5 border-b border-app-line bg-app-chrome px-4 py-1.5 text-center text-xs text-on-app-2"
    >
      <span class="font-mono text-[11px] font-medium tracking-[0.1em] text-accent">TEST DATA</span>
      <span id="demo-data-services">Demo data instead of real data: {Enum.join(
        @services,
        ", "
      )}.</span>
    </div>
    """
  end

  attr :user, :map, required: true

  defp user_menu(assigns) do
    ~H"""
    <div id="user-menu" class="flex flex-nowrap items-center gap-x-4 text-[13px]">
      <span
        id="user-email"
        title={@user.email}
        class="max-w-[220px] truncate text-on-app-muted max-sm:sr-only"
        phx-no-format
      >{@user.email}</span>
      <.link id="settings-link" href={~p"/users/settings"} class={top_bar_link_class()}>
        Settings
      </.link>
      <.link
        id="log-out-link"
        href={~p"/users/log-out"}
        method="delete"
        class={top_bar_link_class()}
      >
        Log out
      </.link>
    </div>
    """
  end

  defp app_sidebar_links do
    [
      %{page: :runs, label: "Results", path: ~p"/app/runs"},
      %{page: :pages, label: "Briefs", path: ~p"/app/pages"}
    ]
  end

  defp new_research_path, do: ~p"/app/research/new"

  defp top_bar_link_class,
    do:
      "inline-flex min-h-target-min items-center text-on-app-2 no-underline transition-colors duration-150 hover:text-on-app"

  defp flash_surface("page"), do: "light"
  defp flash_surface("app"), do: "app"

  defp body_background_class("app"), do: "bg-app"
  defp body_background_class(_light), do: "bg-page"
end
