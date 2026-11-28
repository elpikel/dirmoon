defmodule DirmoonWeb.NewResearchLive do
  @moduledoc """
  Screen 1, New research (`/app/research/new`): a tool view in the app shell,
  no pitch (the owner moved the reference's hero and "how it works" to the
  landing page only). The prompt box that starts a Research Run in the
  User's Account, three example prompts and the estimated API Cost, beside
  the Account's five latest runs. The Market is chosen from the stored
  country and language lists (`Dirmoon.Markets`), starting from the latest
  run's Market (the United States in English for a first run); when no list
  can be loaded the screen says why and can't start a run. The status row says what the run will do
  for the chosen Mode (`Dirmoon.Research.NewRunStatusLine`). See
  `docs/design/README.md` section 8.3.

  The status row's note says how many researches the Account has left
  (`Dirmoon.Billing.researches_left/1`), and nothing for an Account with
  Unpaid Access. With none left the screen says so, with a link to the plan
  screen, and starting a research shows the same instead of a run.

  In Existing Site mode the site's address comes first, with "Read my site":
  an async task drafts the description from the home page
  (`Dirmoon.SiteScans.Description.draft/1`) while the screen stays
  responsive. The draft fills an empty description (or one still equal to
  the previous draft); text the owner typed is never overwritten, and the
  draft is offered beside it instead. The draft's paid request is kept in
  the socket for the domain it was made for, dropped when the address
  changes, and recorded on the run only when the research starts for that
  same domain (`Dirmoon.Research.start_run/3`); the form's params never
  carry it. One draft runs at a time, and a screen makes at most
  five of them.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Billing
  alias Dirmoon.Format
  alias Dirmoon.Markets
  alias Dirmoon.Research
  alias Dirmoon.Research.NewRunStatusLine
  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole
  alias Dirmoon.SiteScans.Description
  alias DirmoonWeb.RunDisplay

  @recent_runs_count 5
  @drafts_per_screen 5
  @drafts_used_up "I've read your site #{@drafts_per_screen} times on this screen. Describe the business yourself, or reload the page to read it again."
  @no_language "Choose the research's language first, so I know which language to write in."
  @draft_crashed "Something went wrong while I read your site. Try again, or describe the business yourself."

  @example_prompts [
    %{
      label: "Coffee roastery with delivery",
      description:
        "A coffee roastery that ships across the country. Freshly roasted beans, a subscription every two weeks and coffee for offices."
    },
    %{
      label: "Mobile bike repair",
      description:
        "Bike repair that comes to the customer. Check-ups, repairs and getting a bike ready for the season without leaving home."
    },
    %{
      label: "Swimming school for adults",
      description:
        "A swimming school for adults. Learning from scratch in small groups, classes in the evenings and at weekends, also for people who are afraid of water."
    }
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:new_research}
      context="new research"
      note={researches_left_note(@researches_left)}
    >
      <:status><span id="new-research-status-line">{@status_line}</span></:status>
      <div id="new-research" class="flex grow flex-col min-[1080px]:flex-row">
        <div
          id="new-research-tool"
          class="flex min-w-0 flex-col min-[1080px]:flex-[3_1_0%] gap-5 border-app-line px-7 pt-6 pb-8 max-sm:px-4 min-[1080px]:border-r max-[1079px]:border-b"
        >
          <h1
            id="new-research-heading"
            class="m-0 text-2xl leading-tight font-bold tracking-[-0.02em]"
          >
            Describe the business.
          </h1>
          <.form
            for={@form}
            id="research-form"
            phx-change="validate"
            phx-submit="start"
            class="w-full max-w-[900px]"
          >
            <.prompt_box
              id="research-prompt-box"
              surface="app"
              class="flex flex-col overflow-hidden transition-colors duration-150 has-[#research-description:focus-visible]:border-on-app-2"
            >
              <.domain_field
                :if={@mode == :existing_site}
                form={@form}
                existing_site?={true}
                reading_site?={@reading_site != nil}
                read_site_error={@read_site_error}
                connection={@search_console_connection}
                class="border-b border-app-line px-[26px] pt-6 pb-[18px] max-sm:px-5"
              />

              <div
                id="research-description-field"
                class="flex flex-col gap-2.5 px-[26px] pt-6 pb-[18px] max-sm:px-5 *:mb-0"
              >
                <label for="research-description" class={field_label_class()}>
                  Your business or idea
                </label>
                <.input
                  field={@form[:description]}
                  id="research-description"
                  type="textarea"
                  surface="app"
                  rows="3"
                  phx-hook=".AutoGrow"
                  placeholder="What do you do, where and for whom?"
                  class="min-h-[92px] w-full resize-none overflow-hidden border-0 bg-transparent p-0 text-[21px] font-medium leading-[1.45] tracking-[-0.01em] text-on-app placeholder:text-on-app-muted focus-visible:outline-none"
                />
                <p
                  :if={@mode == :existing_site and not @description?}
                  id="research-description-hint"
                  class="m-0 text-[13px] leading-normal text-on-app-muted"
                >
                  Paste your address and press Read my site, or describe the business yourself.
                </p>
                <div
                  :if={@offered_draft}
                  id="draft-description"
                  class="flex min-w-0 flex-col items-start gap-2.5 rounded-tile border border-app-line-strong bg-app-raised px-4 py-3"
                >
                  <span class={field_label_class()}>What I read on your site</span>
                  <p
                    id="draft-description-text"
                    class="m-0 text-[15px] leading-normal break-words text-on-app"
                  >
                    {@offered_draft}
                  </p>
                  <.button id="use-draft" variant="outline" phx-click="use_draft">
                    Use this instead
                  </.button>
                </div>
              </div>

              <div
                :if={(@domain_shown? and @mode != :existing_site) or @services_shown?}
                id="research-optional-fields"
                class="flex flex-col gap-5 border-t border-app-line px-[26px] py-[18px] max-sm:px-5"
              >
                <.domain_field
                  :if={@domain_shown? and @mode != :existing_site}
                  form={@form}
                  existing_site?={false}
                />

                <fieldset
                  :if={@services_shown?}
                  id="research-services-field"
                  class="m-0 flex flex-col gap-2 border-0 p-0"
                >
                  <legend class={[field_label_class(), "mb-2 p-0"]}>
                    Priority services · up to {Run.max_priority_services()}
                  </legend>
                  <div class="flex flex-wrap gap-2">
                    <div :for={number <- service_numbers()} class="min-w-0 flex-[1_1_160px] *:mb-0">
                      <label for={"research-service-#{number}"} class="sr-only">Service {number}</label>
                      <.input
                        id={"research-service-#{number}"}
                        name={@form[:priority_services].name <> "[]"}
                        value={Enum.at(@service_values, number - 1)}
                        type="text"
                        surface="app"
                      />
                    </div>
                  </div>
                  <p
                    :for={error <- @service_errors}
                    class="m-0 flex items-center gap-2 text-sm text-on-app"
                  >
                    <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-warn" />{error}
                  </p>
                </fieldset>
              </div>

              <div class="flex flex-wrap items-center gap-3 border-t border-app-line bg-app-field py-3 pr-3.5 pl-5 max-sm:pl-3.5">
                <div class="flex min-w-0 flex-[1_1_320px] flex-wrap gap-2">
                  <div class="relative *:mb-0">
                    <label for="research-mode" class="sr-only">Mode</label>
                    <.input
                      field={@form[:mode]}
                      id="research-mode"
                      type="select"
                      surface="app"
                      options={mode_options()}
                      class={[chip_field_class(), "cursor-pointer appearance-none pr-8 pl-3"]}
                    />
                    <.icon
                      name="hero-chevron-down-mini"
                      class="pointer-events-none absolute top-[11px] right-3 size-3.5 text-on-app-2"
                    />
                  </div>
                  <div :if={!@markets_problem} class="relative max-w-full *:mb-0">
                    <label for="research-country" class="sr-only">Country</label>
                    <.icon
                      name="hero-globe-alt"
                      class="pointer-events-none absolute top-[11px] left-3 size-3.5 text-on-app-muted"
                    />
                    <.input
                      field={@form[:country_code]}
                      id="research-country"
                      type="select"
                      surface="app"
                      options={@country_options}
                      class={[
                        chip_field_class(),
                        "max-w-full cursor-pointer appearance-none pr-3 pl-8"
                      ]}
                    />
                  </div>
                  <div :if={!@markets_problem} class="relative max-w-full *:mb-0">
                    <label for="research-language" class="sr-only">Language</label>
                    <.icon
                      name="hero-language"
                      class="pointer-events-none absolute top-[11px] left-3 size-3.5 text-on-app-muted"
                    />
                    <.input
                      field={@form[:language_code]}
                      id="research-language"
                      type="select"
                      surface="app"
                      options={@language_options}
                      class={[
                        chip_field_class(),
                        "max-w-full cursor-pointer appearance-none pr-3 pl-8"
                      ]}
                    />
                  </div>
                  <div class="relative *:mb-0">
                    <label for="research-city" class="sr-only">City</label>
                    <.icon
                      name="hero-map-pin"
                      class="pointer-events-none absolute top-[11px] left-3 size-3.5 text-on-app-muted"
                    />
                    <.input
                      field={@form[:city]}
                      id="research-city"
                      type="text"
                      surface="app"
                      placeholder="City (optional)"
                      autocomplete="address-level2"
                      class={[chip_field_class(), "w-[190px] pr-3 pl-8 placeholder:text-on-app-muted"]}
                    />
                  </div>
                  <.chip
                    :if={!@domain_shown?}
                    id="show-domain"
                    variant="dashed"
                    phx-click="show_domain"
                  >
                    + Domain
                  </.chip>
                  <.chip
                    :if={!@services_shown?}
                    id="show-services"
                    variant="dashed"
                    phx-click="show_services"
                  >
                    + Services
                  </.chip>
                </div>
                <.button
                  id="start-research"
                  variant="lime"
                  size="large"
                  type="submit"
                  disabled={@markets_problem != nil}
                  phx-disable-with="Starting…"
                  class="flex-none px-[22px] text-base max-sm:w-full"
                >
                  Start research <.icon name="hero-arrow-right" class="size-[18px]" />
                </.button>
              </div>
              <p
                :if={@markets_problem}
                id="markets-unavailable"
                role="alert"
                class="m-0 flex items-start gap-2 border-t border-app-line px-[26px] py-3.5 text-sm leading-normal text-on-app max-sm:px-5"
              >
                <.icon name="hero-exclamation-circle" class="mt-0.5 size-5 shrink-0 text-warn" />
                {@markets_problem}
              </p>
              <p
                :if={@researches_left == 0}
                id="no-researches-left"
                role="alert"
                class="m-0 flex flex-wrap items-center gap-x-2 gap-y-1 border-t border-app-line px-[26px] py-3.5 text-sm leading-normal text-on-app max-sm:px-5"
              >
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-warn" />
                <span>You have no research left.</span>
                <.link
                  id="plan-link"
                  href={~p"/app/billing"}
                  class="inline-flex min-h-target-min items-center font-semibold text-on-app underline underline-offset-4"
                >
                  Buy a research or a monthly plan
                </.link>
              </p>
            </.prompt_box>
          </.form>

          <div class="flex max-w-[900px] flex-wrap items-center gap-x-2.5 gap-y-2">
            <span class="text-[13px] text-on-app-muted">Or start from an example:</span>
            <.chip
              :for={{example, number} <- Enum.with_index(@example_prompts, 1)}
              id={"example-prompt-#{number}"}
              variant="outline"
              phx-click="use_example"
              phx-value-number={number}
            >
              {example.label}
            </.chip>
          </div>
          <span id="estimated-cost" class="font-mono text-xs text-on-app-muted">
            Estimated API cost: about {Format.usd(@estimated_cost)}
          </span>
        </div>

        <section
          id="recent-runs-column"
          aria-labelledby="recent-runs-heading"
          class="flex min-w-0 flex-col min-[1080px]:flex-[2_1_0%] gap-3 px-5 pt-6 pb-8 max-sm:px-4"
        >
          <h2
            id="recent-runs-heading"
            class="m-0 font-mono text-[11px] font-normal uppercase tracking-[0.08em] text-on-app-muted"
          >
            Recent research
          </h2>
          <ul
            id="recent-runs"
            phx-update="stream"
            class="m-0 flex list-none flex-col rounded-tile border border-app-line-strong p-0"
          >
            <li
              id="recent-runs-empty"
              class="hidden px-[18px] py-4 text-sm leading-normal text-on-app-2 only:block"
            >
              No research yet. Start with the description on the left.
            </li>
            <li
              :for={{dom_id, row} <- @streams.recent_runs}
              id={dom_id}
              data-status={row.status}
              class="border-t border-app-line-strong first:border-t-0"
            >
              <.link
                navigate={row.path}
                class="flex min-h-target-min flex-col gap-1.5 px-[18px] py-3.5 text-on-app no-underline transition-colors duration-150 hover:bg-app-raised focus-visible:bg-app-raised focus-visible:outline-none"
              >
                <span class="text-sm font-medium">{row.short_description}</span>
                <span class="flex flex-wrap items-center gap-x-4 gap-y-1 font-mono text-[11px] text-on-app-muted">
                  <.run_status id={"#{dom_id}-status"} status={row.status} label={row.status_label} />
                  <span>{row.date}</span>
                </span>
              </.link>
            </li>
          </ul>
          <.link
            id="all-runs-link"
            navigate={~p"/app/runs"}
            class="inline-flex min-h-target-min items-center gap-1.5 self-start text-sm font-medium text-on-app-2 no-underline transition-colors duration-150 hover:text-on-app"
          >
            All results <.icon name="hero-arrow-right-mini" class="size-4" />
          </.link>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoGrow">
        export default {
          mounted() {
            this.resize()
            this.el.addEventListener("input", () => this.resize())
          },
          updated() {
            this.resize()
          },
          resize() {
            this.el.style.height = "auto"
            this.el.style.height = `${this.el.scrollHeight}px`
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope} = socket.assigns
    recent_runs = Research.list_runs(scope, @recent_runs_count)
    initial_params = Map.put(default_market_params(recent_runs), "mode", initial_mode(params))
    changeset = Research.change_run(scope, initial_params)

    {:ok,
     socket
     |> assign(
       page_title: "New research",
       example_prompts: @example_prompts,
       search_console_connection: SearchConsole.get_connection(scope),
       domain_open?: false,
       services_open?: false,
       params: initial_params,
       researches_left: Billing.researches_left(scope),
       reading_site: nil,
       read_site_error: nil,
       drafts_left: @drafts_per_screen,
       site_draft: nil,
       offered_draft: nil
     )
     |> assign_market_options()
     |> assign_form(changeset)
     |> stream_configure(:recent_runs, dom_id: &"recent-run-#{&1.id}")
     |> stream(:recent_runs, Enum.map(recent_runs, &recent_run_row/1))}
  end

  @impl true
  def handle_event("validate", %{"run" => params}, socket) do
    {:noreply, validate(socket, params)}
  end

  def handle_event("use_example", %{"number" => number}, socket) do
    case example_description(number) do
      nil ->
        {:noreply, socket}

      description ->
        params = Map.put(socket.assigns.params, "description", description)
        {:noreply, validate(socket, params)}
    end
  end

  def handle_event("show_domain", _params, socket) do
    {:noreply, socket |> assign(:domain_open?, true) |> assign_form(socket.assigns.form.source)}
  end

  def handle_event("show_services", _params, socket) do
    {:noreply, socket |> assign(:services_open?, true) |> assign_form(socket.assigns.form.source)}
  end

  def handle_event("read_site", _params, %{assigns: %{reading_site: %{}}} = socket), do: {:noreply, socket}

  def handle_event("read_site", _params, %{assigns: %{drafts_left: 0}} = socket) do
    {:noreply, assign(socket, :read_site_error, @drafts_used_up)}
  end

  def handle_event("read_site", _params, socket) do
    language_name = Ecto.Changeset.get_field(socket.assigns.form.source, :language_name)

    case Run.normalised_domain(socket.assigns.params["domain"]) do
      {:ok, domain} when is_binary(language_name) ->
        {:noreply, start_reading(socket, %{domain: domain, language_name: language_name})}

      {:ok, _domain} ->
        {:noreply, assign(socket, :read_site_error, @no_language)}

      :error ->
        {:noreply, assign(socket, :read_site_error, Description.no_site_message())}
    end
  end

  def handle_event("use_draft", _params, %{assigns: %{offered_draft: draft}} = socket) when is_binary(draft) do
    {:noreply, socket |> assign(:offered_draft, nil) |> validate(Map.put(socket.assigns.params, "description", draft))}
  end

  def handle_event("use_draft", _params, socket), do: {:noreply, socket}

  def handle_event("start", %{"run" => params}, socket) do
    options = [ledger_entries: draft_ledger_entries(socket.assigns.site_draft, params)]

    case Research.start_run(socket.assigns.current_scope, params, options) do
      {:ok, run} ->
        {:noreply, push_navigate(socket, to: ~p"/app/runs/#{run}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(:params, params) |> assign_form(changeset)}

      {:error, :no_researches_left} ->
        {:noreply, socket |> assign(:params, params) |> assign(:researches_left, 0)}
    end
  end

  @impl true
  def handle_async(:draft_description, {:ok, {:ok, draft}}, %{assigns: %{reading_site: %{domain: domain}}} = socket) do
    {:noreply, socket |> assign(:reading_site, nil) |> apply_draft(Map.put(draft, :domain, domain))}
  end

  def handle_async(:draft_description, {:ok, {:error, reason}}, socket) do
    {:noreply, read_failed(socket, reason)}
  end

  def handle_async(:draft_description, {:exit, _reason}, socket) do
    {:noreply, read_failed(socket, @draft_crashed)}
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :existing_site?, :boolean, required: true
  attr :reading_site?, :boolean, default: false
  attr :read_site_error, :string, default: nil
  attr :connection, :any, default: nil
  attr :class, :string, default: nil

  defp domain_field(assigns) do
    ~H"""
    <div id="research-domain-field" class={["flex min-w-0 flex-col gap-2 *:mb-0", @class]}>
      <label for="research-domain" class={field_label_class()}>
        {if @existing_site?, do: "Your site's address (required)", else: "Domain"}
      </label>
      <div class="flex min-w-0 flex-wrap items-start gap-2">
        <div class="min-w-0 flex-[1_1_220px] *:mb-0">
          <.input
            field={@form[:domain]}
            id="research-domain"
            type="text"
            placeholder="yourbusiness.com"
            autocomplete="url"
            spellcheck="false"
            required={@existing_site?}
            surface="app"
          />
        </div>
        <.button
          :if={@existing_site?}
          id="read-site"
          variant="outline"
          phx-click="read_site"
          disabled={@reading_site?}
          aria-busy={to_string(@reading_site?)}
          class="flex-none max-sm:w-full"
        >
          <%= if @reading_site? do %>
            <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Reading…
          <% else %>
            <.icon name="hero-document-magnifying-glass" class="size-4" /> Read my site
          <% end %>
        </.button>
      </div>
      <p
        :if={@read_site_error}
        id="read-site-error"
        role="alert"
        class="m-0 flex min-w-0 items-start gap-2 text-sm leading-normal break-words text-on-app"
      >
        <.icon name="hero-exclamation-circle" class="mt-0.5 size-5 shrink-0 text-warn" />{@read_site_error}
      </p>
      <.search_console_note :if={@existing_site?} connection={@connection} />
    </div>
    """
  end

  attr :connection, :any, required: true

  defp search_console_note(%{connection: nil} = assigns) do
    ~H"""
    <p id="search-console-note" class="m-0 text-[13px] leading-normal text-on-app-2">
      Optional: with Search Console I use Google's own figures for where your site shows up.
      <.link
        id="connect-search-console"
        href={
          ~p"/app/search-console/connect?#{[return_to: ~p"/app/research/new?#{[mode: :existing_site]}"]}"
        }
        class="inline-flex min-h-target-min items-center font-semibold text-on-app underline underline-offset-4"
      >
        Connect Search Console
      </.link>
    </p>
    """
  end

  defp search_console_note(assigns) do
    ~H"""
    <p id="search-console-connected" class="m-0 flex items-center gap-2 text-[13px] text-on-app-2">
      <.icon name="hero-check-circle" class="size-4 shrink-0 text-on-app" />
      Search Console connected ({@connection.google_email})
    </p>
    """
  end

  defp validate(socket, params) do
    changeset =
      socket.assigns.current_scope
      |> Research.change_run(params)
      |> Map.put(:action, :validate)

    socket
    |> forget_other_site(params)
    |> assign(:params, params)
    |> assign_form(changeset)
  end

  defp forget_other_site(socket, params) do
    domain = Run.normalised_domain(params["domain"])

    socket
    |> clear_error_when_address_changed(domain)
    |> keep_draft_only_for(domain)
  end

  defp clear_error_when_address_changed(socket, domain) do
    if Run.normalised_domain(socket.assigns.params["domain"]) == domain,
      do: socket,
      else: assign(socket, :read_site_error, nil)
  end

  defp keep_draft_only_for(socket, domain) do
    if draft_for?(socket.assigns.site_draft, domain),
      do: socket,
      else: assign(socket, site_draft: nil, offered_draft: nil)
  end

  defp start_reading(socket, %{domain: domain} = site) do
    socket
    |> assign(reading_site: %{domain: domain}, read_site_error: nil, drafts_left: socket.assigns.drafts_left - 1)
    |> start_async(:draft_description, fn -> Description.draft(site) end)
  end

  defp apply_draft(socket, %{description: description, ledger_entry: ledger_entry, domain: domain}) do
    if draft_for?(%{domain: domain}, Run.normalised_domain(socket.assigns.params["domain"])) do
      %{params: params, site_draft: previous_draft} = socket.assigns
      socket = assign(socket, site_draft: %{domain: domain, description: description, ledger_entry: ledger_entry})

      if replaceable_description?(params["description"], previous_draft) do
        socket |> assign(:offered_draft, nil) |> validate(Map.put(params, "description", description))
      else
        assign(socket, :offered_draft, description)
      end
    else
      socket
    end
  end

  defp read_failed(%{assigns: %{reading_site: %{domain: domain}}} = socket, reason) do
    if draft_for?(%{domain: domain}, Run.normalised_domain(socket.assigns.params["domain"])),
      do: assign(socket, reading_site: nil, read_site_error: reason),
      else: assign(socket, :reading_site, nil)
  end

  defp replaceable_description?(description, previous_draft) do
    not present?(description) or (previous_draft != nil and String.trim(description) == previous_draft.description)
  end

  defp draft_for?(%{domain: draft_domain}, {:ok, domain}), do: draft_domain == domain
  defp draft_for?(_no_draft, _domain), do: false

  defp draft_ledger_entries(site_draft, params) do
    if draft_for?(site_draft, Run.normalised_domain(params["domain"])), do: [site_draft.ledger_entry], else: []
  end

  defp assign_form(socket, changeset) do
    mode = Ecto.Changeset.get_field(changeset, :mode)
    city? = changeset |> Ecto.Changeset.get_field(:city) |> present?()
    domain? = changeset |> Ecto.Changeset.get_field(:domain) |> present?()
    form = to_form(changeset)
    services_field = form[:priority_services]
    service_values = list_value(services_field.value)

    assign(socket,
      form: form,
      mode: mode,
      domain_shown?: socket.assigns.domain_open? or mode == :existing_site or domain?,
      services_shown?: socket.assigns.services_open? or Enum.any?(service_values, &present?/1),
      service_values: service_values,
      service_errors: service_errors(services_field),
      description?: changeset |> Ecto.Changeset.get_field(:description) |> present?(),
      estimated_cost: Research.estimated_cost(%{city?: city?, mode: mode}),
      status_line: NewRunStatusLine.sentence(%{mode: mode})
    )
  end

  defp researches_left_note(1), do: "1 research left"
  defp researches_left_note(count) when is_integer(count) and count > 1, do: "#{count} researches left"
  defp researches_left_note(_none_or_unlimited), do: nil

  defp recent_run_row(%Run{} = run) do
    %{
      id: run.id,
      short_description: RunDisplay.short_description(run.description),
      status: run.status,
      status_label: RunDisplay.status_label(run.status),
      date: RunDisplay.date(run),
      path: RunDisplay.path(run)
    }
  end

  defp service_errors(field) do
    if used_input?(field), do: Enum.map(field.errors, &translate_error/1), else: []
  end

  defp example_description(number) do
    with {index, ""} when index >= 1 <- Integer.parse(number),
         %{description: description} <- Enum.at(@example_prompts, index - 1) do
      description
    else
      _invalid -> nil
    end
  end

  defp list_value(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp list_value(_value), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp mode_options do
    Enum.map(Run.modes(), &{RunDisplay.mode_label(&1), &1})
  end

  defp assign_market_options(socket) do
    with {:ok, countries} <- Markets.countries(),
         {:ok, languages} <- Markets.languages() do
      assign(socket,
        country_options: Enum.map(countries, &{&1.name, &1.country_code}),
        language_options: Enum.map(languages, &{&1.name, &1.language_code}),
        markets_problem: nil
      )
    else
      {:error, reason} ->
        assign(socket, country_options: [], language_options: [], markets_problem: markets_problem(reason))
    end
  end

  defp markets_problem(:data_for_seo_not_configured) do
    "I can't offer countries and languages yet: the Google search data provider (DataForSEO) isn't configured. Add its login and password, then reload this page."
  end

  defp markets_problem(_reason) do
    "I couldn't load the countries and languages from the Google search data provider (DataForSEO). Reload this page in a moment."
  end

  defp default_market_params([%Run{country_code: country_code, language_code: language_code} | _older_runs]) do
    %{"country_code" => country_code, "language_code" => language_code}
  end

  defp default_market_params([]) do
    %{country_code: country_code, language_code: language_code} = Markets.default_market()
    %{"country_code" => country_code, "language_code" => language_code}
  end

  defp initial_mode(%{"mode" => mode}) do
    if mode in mode_names(), do: mode, else: default_mode()
  end

  defp initial_mode(_params), do: default_mode()

  defp default_mode, do: hd(mode_names())

  defp mode_names, do: Enum.map(Run.modes(), &Atom.to_string/1)

  defp service_numbers do
    last_number = Run.max_priority_services()
    Enum.to_list(1..last_number)
  end

  defp field_label_class, do: "font-mono text-[11px] uppercase tracking-[0.1em] text-on-app-muted"

  defp chip_field_class do
    "min-h-9 rounded-pill border border-app-line-strong bg-app-selected font-sans text-[13px] font-medium text-on-app transition-colors duration-150 hover:border-on-app-muted"
  end
end
