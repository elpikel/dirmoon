defmodule DirmoonWeb.PageLive do
  @moduledoc """
  Screen 4, Brief and page (`/app/pages/:id`): the Brief as one editable form
  on the left with the actions (download the Content File, save the Brief),
  and the Page rendered from the form's current data on the right: the Page
  keeps its own light look inside a browser frame whose bar uses the app's
  gray tokens. Typing re-renders the preview without saving; "Zapisz brief"
  saves. The form shows only for a `:ready` page, the one status whose Brief
  can be edited.

  While Step 8 writes the Brief it says so and turns into the editor when the
  page's PubSub topic reports it ready; a failed Brief can be started again
  while the run's Niches can be chosen. A page waiting on a stopped run links
  to the run's screen to resume it; the screen follows the run's topic too.
  See `docs/design/README.md` sections 8.3 and 8.4 and
  `docs/design/reference/page.html`.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Niches
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.StatusLine
  alias Dirmoon.Pages.Template
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias DirmoonWeb.PageDisplay
  alias DirmoonWeb.RunDisplay

  @not_found_message "Nie znaleziono strony"
  @not_editable_message "Tej strony nie można teraz edytować."
  @invalid_brief_message "Popraw zaznaczone pola briefu."

  @mono_input_class "min-h-target-min w-full rounded-control border border-app-line bg-app-field px-3.5 font-mono text-xs text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-app-line-strong focus:border-on-app-2 focus:outline-none"
  @nested_input_class "min-h-target-min w-full rounded-control border border-app-line-strong bg-app-field px-3.5 text-sm text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-on-app-muted focus:border-on-app-2 focus:outline-none"
  @nested_textarea_class "min-h-[96px] w-full rounded-control border border-app-line-strong bg-app-field px-3.5 py-3 text-sm leading-normal text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-on-app-muted focus:border-on-app-2 focus:outline-none"
  @fieldset_label_class "text-[13px] font-medium text-on-app-2"
  @icon_button_class "inline-flex size-target-min cursor-pointer items-center justify-center rounded-control border border-app-line-strong bg-transparent text-on-app-2 transition-colors duration-150 hover:bg-app-selected hover:text-on-app"

  @business_fields [
    :business_name,
    :phone,
    :email,
    :address,
    :cta_label,
    :closing_prompt,
    :nav_links,
    :plausible_domain
  ]
  @nav_link_count 3

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:pages}
      context={@panel_context}
      note={"Nisza: #{@page.niche.name} · #{RunDisplay.mode_label(@page.run.mode)}"}
    >
      <:status><span id="page-status-line">{@status_line}</span></:status>
      <section id="page-screen" class="flex grow flex-col">
        <h1 class="sr-only">Brief i strona: {@page.niche.name}</h1>
        <.writing :if={@page.status == :writing and not @run_stopped?} />
        <.writing_on_stopped_run :if={@page.status == :writing and @run_stopped?} run={@page.run} />
        <.failed
          :if={@page.status == :failed}
          page={@page}
          retryable?={@retryable?}
          run_stopped?={@run_stopped?}
        />
        <div :if={@form} class="flex grow flex-wrap items-stretch">
          <div class="flex min-w-0 flex-[3_1_300px] flex-col gap-5 border-app-line px-[22px] pt-6 pb-7 min-[860px]:border-r">
            <span class="font-mono text-[11px] uppercase tracking-[0.08em] text-on-app-muted">
              Brief
            </span>
            <.brief_form form={@form} brief={@brief} business_open?={@business_open?} />
            <.actions page={@page} saved?={is_nil(@params)} />
          </div>
          <.preview address={@address} html={@preview_html} />
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Pages.get_page(socket.assigns.current_scope, id) do
      %Page{} = page ->
        if connected?(socket), do: subscribe(page)

        {:ok,
         socket
         |> assign(params: nil, business_open?: false)
         |> assign_page(page)}

      nil ->
        {:ok, redirect_not_found(socket)}
    end
  end

  @impl true
  def handle_info({:page_updated, _page_id}, socket), do: {:noreply, reload_page(socket)}
  def handle_info({:run_updated, _run_id}, socket), do: {:noreply, reload_page(socket)}

  @impl true
  def handle_event("validate", %{"brief" => brief_params}, socket) do
    changeset =
      socket.assigns.page
      |> Pages.change_brief(brief_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_brief(socket, %{changeset: changeset, params: brief_params})}
  end

  def handle_event("save", %{"brief" => brief_params}, socket) do
    case save_brief(socket, brief_params) do
      {:ok, saved_socket} -> {:noreply, put_flash(saved_socket, :info, "Zapisałem brief")}
      {:error, failed_socket} -> {:noreply, failed_socket}
    end
  end

  def handle_event("retry_brief", _params, %{assigns: %{page: %Page{status: :failed} = page, retryable?: true}} = socket) do
    case Niches.choose(socket.assigns.current_scope, page.cluster_id) do
      {:ok, _page} ->
        {:noreply, reload_page(socket)}

      {:error, reason} ->
        message = PageDisplay.choose_error(reason)
        {:noreply, socket |> put_flash(:error, message) |> reload_page()}
    end
  end

  def handle_event("retry_brief", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_business", _params, socket) do
    {:noreply, update(socket, :business_open?, &(not &1))}
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :brief, :any, required: true
  attr :business_open?, :boolean, required: true

  defp brief_form(assigns) do
    business_open? = assigns.business_open? or business_errors?(assigns.form)
    nav_links = nav_link_values(assigns.brief)
    section_count = length(assigns.brief.sections)

    assigns =
      assign(assigns,
        business_open?: business_open?,
        nav_links: nav_links,
        section_count: section_count,
        mono_input_class: @mono_input_class,
        nested_input_class: @nested_input_class,
        nested_textarea_class: @nested_textarea_class,
        fieldset_label_class: @fieldset_label_class,
        icon_button_class: @icon_button_class
      )

    ~H"""
    <.form
      for={@form}
      id="brief-form"
      phx-change="validate"
      phx-submit="save"
      class="flex flex-col"
    >
      <fieldset class="m-0 flex min-w-0 flex-col gap-5 border-0 p-0">
        <.input
          field={@form[:title]}
          id="brief-title"
          label="Tytuł strony"
          surface="app"
          phx-debounce="300"
        />
        <.input
          field={@form[:slug]}
          id="brief-slug"
          label={"Adres: #{PageDisplay.domain_placeholder()}/"}
          class={@mono_input_class}
          surface="app"
          autocomplete="off"
          phx-debounce="300"
        />
        <.input
          field={@form[:breadcrumb]}
          id="brief-breadcrumb"
          label="Ścieżka nad nagłówkiem"
          surface="app"
          phx-debounce="300"
        />
        <.input
          field={@form[:h1]}
          id="brief-h1"
          label="Nagłówek H1"
          surface="app"
          phx-debounce="300"
        />
        <.input
          field={@form[:intro]}
          id="brief-intro"
          type="textarea"
          label="Wstęp"
          surface="app"
          phx-debounce="300"
        />

        <div class="flex flex-col gap-2">
          <span id="brief-sections-label" class={@fieldset_label_class}>Sekcje: pytania klientów</span>
          <ol
            id="brief-sections"
            aria-labelledby="brief-sections-label"
            class="m-0 flex list-none flex-col rounded-tile border border-app-line-strong bg-app-raised p-0"
          >
            <.inputs_for :let={section} field={@form[:sections]}>
              <li
                id={"brief-section-#{section.index}"}
                class="flex flex-col gap-3 border-b border-app-line-strong px-3.5 py-3.5 last:border-b-0"
              >
                <input type="hidden" name="brief[sections_sort][]" value={section.index} />
                <div class="flex items-start gap-3">
                  <span class="pt-[30px] font-mono text-[11px] text-accent">
                    {section_number(section.index)}
                  </span>
                  <div class="flex min-w-0 flex-1 flex-col gap-3">
                    <.input
                      field={section[:question]}
                      label={"Pytanie #{section_number(section.index)}"}
                      class={@nested_input_class}
                      surface="app"
                      phx-debounce="300"
                    />
                    <.input
                      field={section[:answer]}
                      type="textarea"
                      label={"Odpowiedź #{section_number(section.index)}"}
                      class={@nested_textarea_class}
                      surface="app"
                      phx-debounce="300"
                    />
                  </div>
                </div>
                <div class="flex justify-end gap-1.5">
                  <button
                    :if={section.index > 0}
                    id={"move-section-#{section.index}-up"}
                    type="button"
                    name="brief[sections_move_up][]"
                    value={section.index}
                    phx-click={JS.dispatch("change")}
                    aria-label={"Przesuń pytanie #{section_number(section.index)} wyżej"}
                    class={@icon_button_class}
                  >
                    <.icon name="hero-arrow-up-mini" class="size-4" />
                  </button>
                  <button
                    :if={section.index < @section_count - 1}
                    id={"move-section-#{section.index}-down"}
                    type="button"
                    name="brief[sections_move_up][]"
                    value={section.index + 1}
                    phx-click={JS.dispatch("change")}
                    aria-label={"Przesuń pytanie #{section_number(section.index)} niżej"}
                    class={@icon_button_class}
                  >
                    <.icon name="hero-arrow-down-mini" class="size-4" />
                  </button>
                  <button
                    id={"remove-section-#{section.index}"}
                    type="button"
                    name="brief[sections_drop][]"
                    value={section.index}
                    phx-click={JS.dispatch("change")}
                    aria-label={"Usuń pytanie #{section_number(section.index)}"}
                    class={@icon_button_class}
                  >
                    <.icon name="hero-trash-mini" class="size-4" />
                  </button>
                </div>
              </li>
            </.inputs_for>
          </ol>
          <input type="hidden" name="brief[sections_drop][]" />
          <input type="hidden" name="brief[sections_move_up][]" />
          <div
            :if={field_errors(@form[:sections]) != []}
            id="brief-sections-error"
            class="flex flex-col gap-1"
          >
            <p
              :for={message <- field_errors(@form[:sections])}
              class="m-0 flex items-center gap-2 text-sm text-on-app"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-warn" />{message}
            </p>
          </div>
          <button
            id="add-section"
            type="button"
            name="brief[sections_sort][]"
            value="new"
            phx-click={JS.dispatch("change")}
            class="inline-flex min-h-target-min cursor-pointer items-center justify-center gap-2 rounded-control border border-dashed border-app-line-strong bg-transparent px-4 text-sm font-medium text-on-app-2 transition-colors duration-150 hover:bg-app-raised hover:text-on-app"
          >
            <.icon name="hero-plus-mini" class="size-4" /> Dodaj pytanie
          </button>
        </div>

        <.input
          field={@form[:short_answer]}
          id="brief-short-answer"
          type="textarea"
          label="W skrócie: odpowiedź na pierwsze pytanie w jednym zdaniu"
          surface="app"
          phx-debounce="300"
        />

        <div class="flex flex-col gap-2">
          <span id="brief-fact-tiles-label" class={@fieldset_label_class}>Kafelki pod wstępem</span>
          <div
            id="brief-fact-tiles"
            role="group"
            aria-labelledby="brief-fact-tiles-label"
            class="flex flex-col gap-3"
          >
            <.inputs_for :let={fact_tile} field={@form[:fact_tiles]}>
              <div class="grid grid-cols-2 gap-2.5 max-[420px]:grid-cols-1">
                <.input
                  field={fact_tile[:label]}
                  label={"Kafelek #{fact_tile.index + 1}: etykieta"}
                  surface="app"
                  phx-debounce="300"
                />
                <.input
                  field={fact_tile[:value]}
                  label={"Kafelek #{fact_tile.index + 1}: wartość"}
                  surface="app"
                  phx-debounce="300"
                />
              </div>
            </.inputs_for>
          </div>
        </div>

        <div class="flex flex-col gap-3">
          <button
            id="toggle-business"
            type="button"
            phx-click="toggle_business"
            aria-expanded={to_string(@business_open?)}
            aria-controls="brief-business"
            class="inline-flex min-h-target-min cursor-pointer items-center justify-between gap-2 rounded-control border border-app-line-strong bg-transparent px-3.5 text-sm font-medium text-on-app transition-colors duration-150 hover:bg-app-raised"
          >
            Dane firmy
            <.icon
              name={if(@business_open?, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini")}
              class="size-4 text-on-app-muted"
            />
          </button>
          <div
            id="brief-business"
            class={["flex flex-col gap-4", not @business_open? && "hidden"]}
          >
            <.input
              field={@form[:business_name]}
              id="brief-business-name"
              label="Nazwa firmy"
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:phone]}
              id="brief-phone"
              type="tel"
              label="Telefon"
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:email]}
              id="brief-email"
              label="E-mail"
              inputmode="email"
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:address]}
              id="brief-address"
              label="Adres firmy"
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:cta_label]}
              id="brief-cta-label"
              label="Tekst przycisku"
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:closing_prompt]}
              id="brief-closing-prompt"
              label="Zachęta na końcu strony"
              surface="app"
              phx-debounce="300"
            />
            <.input
              :for={{nav_link, position} <- Enum.with_index(@nav_links, 1)}
              id={"brief-nav-link-#{position}"}
              name="brief[nav_links][]"
              value={nav_link}
              label={"Link w menu #{position}"}
              surface="app"
              phx-debounce="300"
            />
            <.input
              field={@form[:plausible_domain]}
              id="brief-plausible-domain"
              label="Domena w Plausible"
              class={@mono_input_class}
              surface="app"
              autocomplete="off"
              phx-debounce="300"
            />
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <span id="brief-phrases-label" class={@fieldset_label_class}>Frazy do pokrycia</span>
          <ul
            id="brief-phrases"
            aria-labelledby="brief-phrases-label"
            class="m-0 flex list-none flex-wrap gap-1.5 p-0 font-mono text-xs"
          >
            <li
              :for={phrase <- ordered_phrases(@brief)}
              data-primary={phrase == @brief.primary_phrase}
              class={[
                "inline-flex min-h-9 items-center rounded-chip px-2.5",
                if(phrase == @brief.primary_phrase,
                  do: "bg-accent text-ink",
                  else: "border border-app-line-strong text-on-app"
                )
              ]}
            >
              {phrase}
            </li>
            <li :if={@brief.phrases == []} class="text-on-app-muted">Brak fraz w briefie.</li>
          </ul>
        </div>
      </fieldset>
    </.form>
    """
  end

  attr :page, Page, required: true
  attr :saved?, :boolean, required: true

  defp actions(assigns) do
    ~H"""
    <div
      id="page-actions"
      class="sticky bottom-0 z-10 -mx-[22px] -mb-7 mt-auto flex flex-wrap items-center gap-2.5 border-t border-app-line bg-app px-[22px] pt-4 pb-5"
    >
      <.button
        id="download-page"
        variant="lime"
        size="large"
        class="basis-full"
        href={~p"/app/pages/#{@page}/file"}
      >
        Pobierz plik treści
      </.button>
      <.button
        id="save-brief"
        name="save"
        type="submit"
        form="brief-form"
        variant="outline"
        size="large"
        phx-disable-with="Zapisuję…"
        class="flex-[1_1_auto]"
      >
        Zapisz brief
      </.button>
      <span
        id="brief-save-state"
        data-saved={@saved?}
        class={[
          "flex basis-full items-center gap-1.5 font-mono text-[11px]",
          if(@saved?, do: "text-on-app-muted", else: "text-warn")
        ]}
      >
        <.icon
          name={if(@saved?, do: "hero-check-mini", else: "hero-pencil-square-mini")}
          class="size-[13px]"
        />
        {if(@saved?, do: "Zapisano", else: "Niezapisane zmiany")}
      </span>
    </div>
    """
  end

  attr :address, :string, required: true
  attr :html, :string, required: true

  defp preview(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-[7_1_496px] flex-col gap-3 border-app-line px-6 pt-6 pb-7 max-[859px]:border-t max-sm:px-4">
      <div class="flex flex-wrap items-center justify-between gap-2 font-mono text-[11px] text-on-app-muted">
        <span class="uppercase tracking-[0.08em]">Podgląd strony</span>
        <span>Szablon stały, treść z briefu</span>
      </div>
      <div
        id="preview-frame"
        class="flex flex-col overflow-hidden rounded-[14px] border border-app-line-strong bg-white text-ink min-[860px]:max-h-[2400px] min-[860px]:flex-1"
      >
        <div
          id="preview-frame-bar"
          class="flex items-center gap-2.5 border-b border-app-line bg-app-chrome px-3.5 py-2.5"
        >
          <span
            id="preview-address"
            class="flex min-w-0 flex-1 items-center gap-2 rounded-[8px] border border-app-line bg-app-field px-3 py-[7px] font-mono text-xs text-on-app-2"
          >
            <.icon name="hero-lock-closed-mini" class="size-3 shrink-0 text-on-app-muted" />
            <span class="truncate">{@address}</span>
          </span>
        </div>
        <iframe
          id="page-preview"
          srcdoc={@html}
          sandbox=""
          title="Podgląd strony"
          class="block h-[880px] w-full border-0 bg-white max-sm:h-[640px] min-[860px]:h-auto min-[860px]:min-h-[max(880px,70vh)] min-[860px]:flex-1"
        ></iframe>
      </div>
    </div>
    """
  end

  defp writing(assigns) do
    ~H"""
    <div id="page-writing" class="flex flex-col items-start gap-3 px-7 py-10 max-sm:px-5">
      <span class="flex items-center gap-2.5 text-[22px] leading-snug font-bold">
        <.icon name="hero-arrow-path" class="size-5 motion-safe:animate-spin text-accent" />
        Piszę brief dla tej niszy.
      </span>
      <p class="m-0 max-w-[560px] text-[15px] leading-normal text-on-app-2">
        Tytuł, nagłówek, pytania klientów z odpowiedziami i frazy do pokrycia. Ten ekran sam zamieni się w edytor, gdy skończę.
      </p>
    </div>
    """
  end

  attr :run, Run, required: true

  defp writing_on_stopped_run(assigns) do
    ~H"""
    <div id="page-waiting" class="flex flex-col items-start gap-3 px-7 py-10 max-sm:px-5">
      <span class="text-[22px] leading-snug font-bold">Brief czeka na wznowienie researchu.</span>
      <.run_stopped_note
        id="page-run-stopped"
        link_id="page-resume-link"
        run={@run}
        class="max-w-[560px]"
      >
        Research jest zatrzymany. Wznów go, a dokończę brief.
      </.run_stopped_note>
    </div>
    """
  end

  attr :page, Page, required: true
  attr :retryable?, :boolean, required: true
  attr :run_stopped?, :boolean, required: true

  defp failed(assigns) do
    ~H"""
    <div id="page-failed" class="flex flex-col items-start gap-3 px-7 py-10 max-sm:px-5">
      <span class="text-[22px] leading-snug font-bold">Nie udało mi się napisać briefu.</span>
      <p id="page-error" class="m-0 max-w-[560px] text-[15px] leading-normal text-on-app-2">
        {@page.error || "Nie znam powodu."}
      </p>
      <.run_stopped_note
        :if={@run_stopped?}
        id="page-run-stopped"
        link_id="page-resume-link"
        run={@page.run}
        class="max-w-[560px]"
      >
        Research jest zatrzymany. Wznów go, a potem spróbujesz ponownie.
      </.run_stopped_note>
      <.button
        :if={@retryable?}
        id="retry-brief"
        variant="lime"
        size="large"
        phx-click="retry_brief"
        phx-disable-with="Ponawiam…"
      >
        Spróbuj ponownie
      </.button>
    </div>
    """
  end

  defp subscribe(page) do
    Pages.subscribe(page)
    Research.subscribe(page.run)
  end

  defp assign_page(socket, %Page{} = page) do
    short_description = RunDisplay.short_description(page.run.description)
    run_stopped? = page.run.status == :stopped

    socket
    |> assign(
      page: page,
      page_title: PageDisplay.title(page),
      status_line: StatusLine.sentence(page),
      panel_context: panel_context(short_description, page),
      run_stopped?: run_stopped?,
      retryable?: Run.choosable?(page.run)
    )
    |> assign_stored_brief()
  end

  defp assign_stored_brief(%{assigns: %{page: %Page{status: status}}} = socket) when status in [:writing, :failed] do
    assign(socket, form: nil, brief: nil, preview_html: nil, address: nil, params: nil)
  end

  defp assign_stored_brief(%{assigns: %{page: page, params: nil}} = socket) do
    changeset = Pages.change_brief(page)
    assign_brief(socket, %{changeset: changeset, params: nil})
  end

  defp assign_stored_brief(%{assigns: %{page: page, params: params}} = socket) do
    changeset =
      page
      |> Pages.change_brief(params)
      |> Map.put(:action, :validate)

    assign_brief(socket, %{changeset: changeset, params: params})
  end

  defp assign_brief(socket, %{changeset: changeset, params: params}) do
    %{page: page} = socket.assigns
    brief = Ecto.Changeset.apply_changes(changeset)
    preview_html = Template.render(brief, %{mode: page.run.mode})

    assign(socket,
      form: to_form(changeset),
      brief: brief,
      params: params,
      preview_html: preview_html,
      address: preview_address(brief)
    )
  end

  defp save_brief(socket, brief_params) do
    %{current_scope: scope, page: page} = socket.assigns

    case Pages.update_brief(scope, page.id, brief_params) do
      {:ok, _page} ->
        {:ok, socket |> assign(:params, nil) |> reload_page()}

      {:error, %Ecto.Changeset{} = changeset} ->
        failed_socket =
          socket
          |> assign_brief(%{changeset: changeset, params: brief_params})
          |> put_flash(:error, @invalid_brief_message)

        {:error, failed_socket}

      {:error, :not_editable} ->
        {:error, socket |> put_flash(:error, @not_editable_message) |> reload_page()}

      {:error, :not_found} ->
        {:error, redirect_not_found(socket)}
    end
  end

  defp reload_page(socket) do
    %{current_scope: scope, page: page} = socket.assigns

    case Pages.get_page(scope, page.id) do
      %Page{} = reloaded_page -> assign_page(socket, reloaded_page)
      nil -> redirect_not_found(socket)
    end
  end

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, @not_found_message)
    |> push_navigate(to: ~p"/app/pages")
  end

  defp panel_context(short_description, %Page{brief: %{slug: slug}}) when is_binary(slug) and slug != "" do
    "#{String.downcase(short_description)} / #{slug}"
  end

  defp panel_context(short_description, _page_without_slug), do: String.downcase(short_description)

  defp preview_address(brief), do: PageDisplay.address(brief.slug)

  defp ordered_phrases(%{phrases: phrases, primary_phrase: primary_phrase}) do
    {primary, others} = Enum.split_with(phrases, &(&1 == primary_phrase))
    primary ++ others
  end

  defp nav_link_values(%{nav_links: nav_links}) do
    padding = List.duplicate("", @nav_link_count)

    nav_links
    |> Enum.concat(padding)
    |> Enum.take(@nav_link_count)
  end

  defp business_errors?(form) do
    Enum.any?(@business_fields, &(field_errors(form[&1]) != []))
  end

  defp field_errors(%Phoenix.HTML.FormField{errors: errors}), do: Enum.map(errors, &translate_error/1)

  defp section_number(index) do
    position = index + 1

    position
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end
