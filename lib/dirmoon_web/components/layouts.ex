defmodule DirmoonWeb.Layouts do
  @moduledoc """
  The embedded root template plus the app, landing and auth layouts, and the
  flash group they render. All three sit on the dotted page background
  (`page-dots`) from `docs/design/README.md` section 8.2.
  """
  use DirmoonWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the signed-in app shell: the floating nav card with "Wyniki",
  "Strony", the dark "Nowy research" button and, when signed in, the user's
  email with "Ustawienia" and "Wyloguj" links, over the 1180px content
  column (32px side padding, 16px on phones).

      <Layouts.app flash={@flash} current_scope={@current_scope} active={:runs}>
        <div id="results">...</div>
      </Layouts.app>

  `active` marks its nav link with `aria-current="page"`. `demo_data` shows
  the "DANE TESTOWE" strip above the nav; it defaults to `Dirmoon.demo_data?/0`.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom,
    default: nil,
    values: [nil, :runs, :pages],
    doc: "the nav link of the page being shown"

  attr :demo_data, :boolean, doc: "whether demo adapters stand in for real providers; defaults to `Dirmoon.demo_data?/0`"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:nav_links, app_nav_links())
      |> assign_new(:demo_data, &Dirmoon.demo_data?/0)

    ~H"""
    <.page_shell layout="app">
      <:header>
        <.demo_data_banner :if={@demo_data} />
        <.nav_card id="app-nav" home_href={new_research_path()}>
          <.nav_link :for={link <- @nav_links} href={link.path} active={link.page == @active}>
            {link.label}
          </.nav_link>
          <.button variant="dark" href={new_research_path()}>Nowy research</.button>
          <.user_menu :if={@current_scope} user={@current_scope.user} />
        </.nav_card>
      </:header>
      {render_slot(@inner_block)}
    </.page_shell>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the signed-out landing shell: the same page and nav card as the
  app, with the `nav` slot on the right-hand side (sign-in link, sign-up
  button).

      <Layouts.landing flash={@flash}>
        <:nav><.nav_link href={~p"/users/log-in"}>Zaloguj się</.nav_link></:nav>
        <section id="hero">...</section>
      </Layouts.landing>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :nav, doc: "the right-hand side of the nav card"
  slot :inner_block, required: true

  def landing(assigns) do
    ~H"""
    <.page_shell layout="landing">
      <:header>
        <.nav_card id="landing-nav">{render_slot(@nav)}</.nav_card>
      </:header>
      {render_slot(@inner_block)}
    </.page_shell>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the sign-in shell: the mark and wordmark above a centred white card
  on the dotted page.

      <Layouts.auth flash={@flash}>
        <h1>Zaloguj się</h1>
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
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp demo_data_banner(assigns) do
    ~H"""
    <div
      id="demo-data-banner"
      role="status"
      class="mx-auto mb-3 flex w-full max-w-content flex-wrap items-center justify-center gap-x-3 gap-y-1 rounded-control bg-ink px-4 py-2 text-center text-[13px] text-white"
    >
      <span class="font-mono text-xs font-medium tracking-[0.1em] text-accent">DANE TESTOWE</span>
      <span>Aplikacja używa danych demonstracyjnych, nie prawdziwych wyników.</span>
    </div>
    """
  end

  attr :user, :map, required: true

  defp user_menu(assigns) do
    ~H"""
    <div id="user-menu" class="flex flex-wrap items-center gap-x-5 gap-y-1">
      <span id="user-email" class="max-w-[220px] truncate text-body-muted">{@user.email}</span>
      <.nav_link id="settings-link" href={~p"/users/settings"}>Ustawienia</.nav_link>
      <.nav_link id="log-out-link" href={~p"/users/log-out"} method="delete">Wyloguj</.nav_link>
    </div>
    """
  end

  attr :layout, :string, required: true, doc: "names the layout in data-layout"
  slot :header, required: true
  slot :inner_block, required: true

  defp page_shell(assigns) do
    ~H"""
    <div data-layout={@layout} class="page-dots flex min-h-screen flex-col font-sans text-ink">
      <header class="px-gutter-phone pt-4 sm:px-gutter">{render_slot(@header)}</header>
      <main class="mx-auto flex w-full max-w-content grow flex-col px-gutter-phone pt-16 pb-[88px] sm:px-gutter">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  defp app_nav_links do
    [
      %{page: :runs, label: "Wyniki", path: ~p"/app/runs"},
      %{page: :pages, label: "Strony", path: ~p"/app/pages"}
    ]
  end

  defp new_research_path, do: ~p"/app/research/new"
end
