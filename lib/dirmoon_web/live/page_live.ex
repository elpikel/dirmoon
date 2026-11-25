defmodule DirmoonWeb.PageLive do
  @moduledoc """
  The brief screen (`/app/pages/:id`): a Page's Brief as one editable form,
  the plan and the text of one page that the owner hands to whoever builds
  their site. dirmoon builds no page from it. The page's text (title,
  address, H1, intro, customer questions with answers, short answer) fills
  the wide column; the Phrases to cover and the owner's business details sit
  beside it, and under it on narrow screens. Typing marks the Brief unsaved;
  "Save brief" saves. The form shows only for a `:ready` page, the one status
  whose Brief can be edited.

  While Step 8 writes the Brief it says so and turns into the editor when the
  page's PubSub topic reports it ready; a failed Brief can be started again
  while the run's Niches can be chosen. A page waiting on a stopped run links
  to the run's screen to resume it; the screen follows the run's topic too.
  See `docs/design/README.md` sections 8.3 and 8.4 and
  `docs/design/reference/page.html` (the handover still draws a page preview
  that dirmoon no longer builds).
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Niches
  alias Dirmoon.Pages
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.StatusLine
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias DirmoonWeb.PageDisplay
  alias DirmoonWeb.RunDisplay

  @not_found_message "Page not found"
  @not_editable_message "This page can't be edited now."
  @invalid_brief_message "Fix the marked fields of the brief."

  @mono_input_class "min-h-target-min w-full rounded-control border border-app-line bg-app-field px-3.5 font-mono text-xs text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-app-line-strong focus:border-on-app-2 focus:outline-none"
  @nested_input_class "min-h-target-min w-full rounded-control border border-app-line-strong bg-app-field px-3.5 text-sm text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-on-app-muted focus:border-on-app-2 focus:outline-none"
  @nested_textarea_class "min-h-[96px] w-full rounded-control border border-app-line-strong bg-app-field px-3.5 py-3 text-sm leading-normal text-on-app transition-colors duration-150 placeholder:text-on-app-muted hover:border-on-app-muted focus:border-on-app-2 focus:outline-none"
  @fieldset_label_class "text-[13px] font-medium text-on-app-2"
  @block_label_class "m-0 p-0 font-mono text-[11px] uppercase tracking-[0.08em] text-on-app-muted"
  @icon_button_class "inline-flex size-target-min cursor-pointer items-center justify-center rounded-control border border-app-line-strong bg-transparent text-on-app-2 transition-colors duration-150 hover:bg-app-selected hover:text-on-app"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:pages}
      context={@panel_context}
      note={"Niche: #{@page.niche.name} · #{RunDisplay.mode_label(@page.run.mode)}"}
    >
      <:status><span id="page-status-line">{@status_line}</span></:status>
      <section id="page-screen" class="flex grow flex-col">
        <h1 class="sr-only">Brief: {@page.niche.name}</h1>
        <.writing :if={@page.status == :writing and not @run_stopped?} />
        <.writing_on_stopped_run :if={@page.status == :writing and @run_stopped?} run={@page.run} />
        <.failed
          :if={@page.status == :failed}
          page={@page}
          retryable?={@retryable?}
          run_stopped?={@run_stopped?}
        />
        <div :if={@form} id="brief-screen" class="flex grow flex-col">
          <.brief_form form={@form} brief={@brief} />
          <.actions saved?={is_nil(@params)} />
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
         |> assign(params: nil)
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
      {:ok, saved_socket} -> {:noreply, put_flash(saved_socket, :info, "I saved the brief.")}
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :brief, :any, required: true

  defp brief_form(assigns) do
    section_count = length(assigns.brief.sections)

    assigns =
      assign(assigns,
        section_count: section_count,
        block_label_class: @block_label_class,
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
      class="flex grow flex-wrap items-stretch"
    >
      <div
        id="brief-text"
        class="flex min-w-0 flex-[3_1_420px] flex-col gap-7 border-app-line px-[22px] pt-6 pb-8 max-sm:px-4"
      >
        <fieldset class="m-0 flex min-w-0 max-w-[820px] flex-col gap-5 border-0 p-0">
          <legend class={[@block_label_class, "mb-5"]}>The page</legend>
          <.input
            field={@form[:title]}
            id="brief-title"
            label="Page title"
            surface="app"
            phx-debounce="300"
          />
          <.input
            field={@form[:slug]}
            id="brief-slug"
            label="Address: the part after your domain"
            class={@mono_input_class}
            surface="app"
            autocomplete="off"
            phx-debounce="300"
          />
          <.input
            field={@form[:h1]}
            id="brief-h1"
            label="H1 heading"
            surface="app"
            phx-debounce="300"
          />
          <.input
            field={@form[:intro]}
            id="brief-intro"
            type="textarea"
            label="Intro"
            surface="app"
            phx-debounce="300"
          />
        </fieldset>

        <fieldset class="m-0 flex min-w-0 max-w-[820px] flex-col gap-5 border-0 p-0">
          <legend class={[@block_label_class, "mb-5"]}>The sections</legend>
          <div class="flex flex-col gap-2">
            <span id="brief-sections-label" class={@fieldset_label_class}>Customer questions with answers</span>
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
                        label={"Question #{section_number(section.index)}"}
                        class={@nested_input_class}
                        surface="app"
                        phx-debounce="300"
                      />
                      <.input
                        field={section[:answer]}
                        type="textarea"
                        label={"Answer #{section_number(section.index)}"}
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
                      aria-label={"Move question #{section_number(section.index)} up"}
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
                      aria-label={"Move question #{section_number(section.index)} down"}
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
                      aria-label={"Remove question #{section_number(section.index)}"}
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
              <.icon name="hero-plus-mini" class="size-4" /> Add question
            </button>
          </div>

          <.input
            field={@form[:short_answer]}
            id="brief-short-answer"
            type="textarea"
            label="Short answer: the answer to the first question in one sentence"
            surface="app"
            phx-debounce="300"
          />
        </fieldset>
      </div>

      <div
        id="brief-side"
        class="flex min-w-0 flex-[2_1_300px] flex-col gap-7 border-app-line bg-app-raised px-[22px] pt-6 pb-8 max-sm:px-4 min-[860px]:border-l max-[859px]:border-t"
      >
        <div class="flex flex-col gap-3">
          <span id="brief-phrases-label" class={@block_label_class}>Phrases to cover</span>
          <p class="m-0 text-[13px] leading-normal text-on-app-2">
            What people really type for this niche. The page should use them, the first one most of all.
          </p>
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
            <li :if={@brief.phrases == []} class="text-on-app-muted">No phrases in the brief.</li>
          </ul>
        </div>

        <fieldset id="brief-business" class="m-0 flex min-w-0 flex-col gap-4 border-0 p-0">
          <legend class={[@block_label_class, "mb-3"]}>Business details</legend>
          <p class="m-0 text-[13px] leading-normal text-on-app-2">
            Yours to fill in. I never write a price, phone, e-mail or address: where the text needs one it says [PRICE], [PHONE] and so on.
          </p>
          <.input
            field={@form[:business_name]}
            id="brief-business-name"
            label="Business name"
            surface="app"
            phx-debounce="300"
          />
          <.input
            field={@form[:phone]}
            id="brief-phone"
            type="tel"
            label="Phone"
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
            label="Business address"
            surface="app"
            phx-debounce="300"
          />
        </fieldset>
      </div>
    </.form>
    """
  end

  attr :saved?, :boolean, required: true

  defp actions(assigns) do
    ~H"""
    <div
      id="page-actions"
      class="sticky bottom-0 z-10 flex flex-wrap items-center gap-x-4 gap-y-2.5 border-t border-app-line bg-app px-[22px] pt-4 pb-5 max-sm:px-4"
    >
      <.button
        id="save-brief"
        name="save"
        type="submit"
        form="brief-form"
        variant="lime"
        size="large"
        phx-disable-with="Saving…"
        class="max-sm:flex-[1_1_auto]"
      >
        Save brief
      </.button>
      <span
        id="brief-save-state"
        data-saved={@saved?}
        class={[
          "flex items-center gap-1.5 font-mono text-[11px]",
          if(@saved?, do: "text-on-app-muted", else: "text-warn")
        ]}
      >
        <.icon
          name={if(@saved?, do: "hero-check-mini", else: "hero-pencil-square-mini")}
          class="size-[13px]"
        />
        {if(@saved?, do: "Saved", else: "Unsaved changes")}
      </span>
    </div>
    """
  end

  defp writing(assigns) do
    ~H"""
    <div id="page-writing" class="flex flex-col items-start gap-3 px-7 py-10 max-sm:px-5">
      <span class="flex items-center gap-2.5 text-[22px] leading-snug font-bold">
        <.icon name="hero-arrow-path" class="size-5 motion-safe:animate-spin text-accent" />
        I'm writing the brief for this niche.
      </span>
      <p class="m-0 max-w-[560px] text-[15px] leading-normal text-on-app-2">
        Title, heading, customer questions with answers and phrases to cover. This screen turns into the editor by itself when I'm done.
      </p>
    </div>
    """
  end

  attr :run, Run, required: true

  defp writing_on_stopped_run(assigns) do
    ~H"""
    <div id="page-waiting" class="flex flex-col items-start gap-3 px-7 py-10 max-sm:px-5">
      <span class="text-[22px] leading-snug font-bold">The brief is waiting for the research to resume.</span>
      <.run_stopped_note
        id="page-run-stopped"
        link_id="page-resume-link"
        run={@run}
        class="max-w-[560px]"
      >
        The research is stopped. Resume it and I'll finish the brief.
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
      <span class="text-[22px] leading-snug font-bold">I couldn't write the brief.</span>
      <p id="page-error" class="m-0 max-w-[560px] text-[15px] leading-normal text-on-app-2">
        {@page.error || "I don't know why."}
      </p>
      <.run_stopped_note
        :if={@run_stopped?}
        id="page-run-stopped"
        link_id="page-resume-link"
        run={@page.run}
        class="max-w-[560px]"
      >
        The research is stopped. Resume it, then try again.
      </.run_stopped_note>
      <.button
        :if={@retryable?}
        id="retry-brief"
        variant="lime"
        size="large"
        phx-click="retry_brief"
        phx-disable-with="Retrying…"
      >
        Try again
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
    assign(socket, form: nil, brief: nil, params: nil)
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
    brief = Ecto.Changeset.apply_changes(changeset)

    assign(socket, form: to_form(changeset), brief: brief, params: params)
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

  defp ordered_phrases(%{phrases: phrases, primary_phrase: primary_phrase}) do
    {primary, others} = Enum.split_with(phrases, &(&1 == primary_phrase))
    primary ++ others
  end

  defp field_errors(%Phoenix.HTML.FormField{errors: errors}), do: Enum.map(errors, &translate_error/1)

  defp section_number(index) do
    position = index + 1

    position
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end
