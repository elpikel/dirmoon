defmodule DirmoonWeb.NewResearchLive do
  @moduledoc """
  Screen 1, New research (`/app/research/new`): a tool view in the app shell,
  no pitch (the owner moved the reference's hero and "how it works" to the
  landing page only). The prompt box that starts a Research Run in the
  User's Account, three example prompts and the estimated API Cost, beside
  the Account's five latest runs. The status row says what the run will do
  for the chosen Mode (`Dirmoon.Research.NewRunStatusLine`). See
  `docs/design/README.md` section 8.3.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Format
  alias Dirmoon.Research
  alias Dirmoon.Research.NewRunStatusLine
  alias Dirmoon.Research.Run
  alias Dirmoon.SearchConsole
  alias DirmoonWeb.RunDisplay

  @recent_runs_count 5

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
              </div>

              <div
                :if={@domain_shown? or @services_shown?}
                id="research-optional-fields"
                class="flex flex-col gap-5 border-t border-app-line px-[26px] py-[18px] max-sm:px-5"
              >
                <div
                  :if={@domain_shown?}
                  id="research-domain-field"
                  class="flex flex-col gap-2 *:mb-0"
                >
                  <label for="research-domain" class={field_label_class()}>
                    Domain{if @mode == :existing_site, do: " (required)"}
                  </label>
                  <.input
                    field={@form[:domain]}
                    id="research-domain"
                    type="text"
                    placeholder="yourbusiness.com"
                    autocomplete="url"
                    spellcheck="false"
                    required={@mode == :existing_site}
                    surface="app"
                  />
                  <.search_console_note
                    :if={@mode == :existing_site}
                    connection={@search_console_connection}
                  />
                </div>

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
                  <div class="relative *:mb-0">
                    <label for="research-country" class="sr-only">Country and language</label>
                    <.icon
                      name="hero-globe-alt"
                      class="pointer-events-none absolute top-[11px] left-3 size-3.5 text-on-app-muted"
                    />
                    <.input
                      field={@form[:country_code]}
                      id="research-country"
                      type="select"
                      surface="app"
                      options={location_options()}
                      class={[chip_field_class(), "cursor-pointer appearance-none pr-3 pl-8"]}
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
                  phx-disable-with="Starting…"
                  class="flex-none px-[22px] text-base max-sm:w-full"
                >
                  Start research <.icon name="hero-arrow-right" class="size-[18px]" />
                </.button>
              </div>
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
    initial_params = %{"mode" => initial_mode(params), "country_code" => default_country_code()}
    changeset = Research.change_run(scope, initial_params)
    recent_runs = Research.list_runs(scope, @recent_runs_count)

    {:ok,
     socket
     |> assign(
       page_title: "New research",
       example_prompts: @example_prompts,
       search_console_connection: SearchConsole.get_connection(scope),
       domain_open?: false,
       services_open?: false,
       params: initial_params
     )
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

  def handle_event("start", %{"run" => params}, socket) do
    case Research.start_run(socket.assigns.current_scope, params) do
      {:ok, run} ->
        {:noreply, push_navigate(socket, to: ~p"/app/runs/#{run}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(:params, params) |> assign_form(changeset)}
    end
  end

  attr :connection, :any, required: true

  defp search_console_note(%{connection: nil} = assigns) do
    ~H"""
    <p id="search-console-note" class="m-0 text-[13px] leading-normal text-on-app-2">
      Without Search Console, step 6 (the site's current positions) is skipped.
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
    |> assign(:params, params)
    |> assign_form(changeset)
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
      estimated_cost: Research.estimated_cost(%{city?: city?}),
      status_line:
        NewRunStatusLine.sentence(%{
          mode: mode,
          search_console_connected?: not is_nil(socket.assigns.search_console_connection)
        })
    )
  end

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

  defp location_options do
    Enum.map(Run.locations(), &{&1.label, &1.country_code})
  end

  defp initial_mode(%{"mode" => mode}) do
    if mode in mode_names(), do: mode, else: default_mode()
  end

  defp initial_mode(_params), do: default_mode()

  defp default_mode, do: hd(mode_names())

  defp mode_names, do: Enum.map(Run.modes(), &Atom.to_string/1)

  defp default_country_code do
    [%{country_code: country_code} | _other_locations] = Run.locations()
    country_code
  end

  defp service_numbers do
    last_number = Run.max_priority_services()
    Enum.to_list(1..last_number)
  end

  defp field_label_class, do: "font-mono text-[11px] uppercase tracking-[0.1em] text-on-app-muted"

  defp chip_field_class do
    "min-h-9 rounded-pill border border-app-line-strong bg-app-selected font-sans text-[13px] font-medium text-on-app transition-colors duration-150 hover:border-on-app-muted"
  end
end
