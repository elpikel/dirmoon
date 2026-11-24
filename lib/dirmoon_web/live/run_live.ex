defmodule DirmoonWeb.RunLive do
  @moduledoc """
  Screen 2, Research in progress (`/app/runs/:id`), in the app shell: the
  run's nine Steps on the left, the running Step's detail on the right with
  the actions at its bottom, the status sentence in the status row, stop
  and resume, and the API Cost so far. Updates live from the run's PubSub
  topic and goes to the results once Step 7 finishes. See
  `docs/design/README.md` section 8.3 and `docs/design/reference/run.html`.
  """
  use DirmoonWeb, :live_view

  alias Dirmoon.Competition
  alias Dirmoon.Polish
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.StatusLine
  alias Dirmoon.Research.Steps
  alias DirmoonWeb.RunDisplay

  @competition_step Steps.number!(:competition)
  @publish_step Steps.number!(:publish)
  @checked_phrases_limit 8
  @not_found_message "Nie znaleziono researchu"

  @step_hints %{
    seeds: "Frazy startowe i pytania klientów",
    expansion: "Frazy, które ludzie naprawdę wpisują",
    volumes: "Wyszukiwania w kraju i w mieście, CPC, trend 12 miesięcy",
    filter_and_group: "Odsiew fraz spoza oferty, grupowanie w nisze",
    competition: "Kto trzyma top 10 dla najlepszych fraz",
    current_positions: "Pozycje strony z Search Console",
    scoring: "Wolumen, CPC, słabość konkurencji",
    brief_and_content: "Po wyborze niszy",
    publish: "Landing na Netlify"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active={:runs}
      context={@context_line}
      note={RunDisplay.mode_label(@run.mode)}
    >
      <:status><span id="run-status-line">{@status_line}</span></:status>
      <section id="run" class="flex grow flex-col min-[1080px]:flex-row">
        <h1 class="sr-only">Research: {@short_description}</h1>
        <ol
          id="run-steps"
          class="m-0 min-w-0 list-none border-app-line p-0 min-[1080px]:w-[min(42%,460px)] min-[1080px]:flex-none min-[1080px]:border-r max-[1079px]:border-b"
        >
          <li
            :for={step <- @step_rows}
            id={"step-#{step.number}"}
            data-status={step.status}
            class={[
              "flex items-center gap-3.5 border-b border-app-line px-5 py-[15px] last:border-b-0",
              step.status == :running && "bg-app-raised"
            ]}
          >
            <span class={[
              "font-mono text-[11px]",
              if(step.status == :running, do: "text-on-app", else: "text-on-app-muted")
            ]}>
              {step.label_number}
            </span>
            <span class="flex min-w-0 flex-auto flex-col gap-[3px]">
              <span class={["text-sm", step_name_class(step.status)]}>{step.name}</span>
              <span class={[
                "text-xs",
                if(step.status == :running, do: "text-on-app-2", else: "text-on-app-muted")
              ]}>
                {step.summary}
              </span>
              <span
                :if={step.status == :failed and step.error}
                id={"step-#{step.number}-error"}
                class="text-xs text-warn"
              >
                {step.error}
              </span>
            </span>
            <.step_status id={"step-#{step.number}-status"} status={step.status} />
          </li>
        </ol>

        <div
          id="run-detail"
          class="flex min-w-0 grow flex-col gap-[22px] px-7 pt-6 pb-7 max-sm:px-5"
        >
          <.competition_detail
            :if={@detail == :competition}
            step={@current_step}
            progress={@progress}
            checked_phrases={@streams.checked_phrases}
          />
          <.step_detail :if={@detail == :step} step={@current_step} />
          <.state_detail
            :if={@detail == :state}
            run={@run}
            step={@current_step}
            results_path={@results_path}
            published_url={@published_url}
          />

          <div class="mt-auto flex flex-wrap items-center gap-2.5">
            <.button
              :if={@run.status in [:running, :stopped, :failed]}
              id="show-phrases"
              variant={if(@run.status == :running, do: "lime", else: "outline")}
              size="large"
              navigate={@results_path}
            >
              Pokaż dotychczasowe frazy
            </.button>
            <.button
              :if={@run.status == :running}
              id="stop-run"
              variant="outline"
              size="large"
              phx-click="stop"
              phx-disable-with="Zatrzymuję…"
            >
              Zatrzymaj
            </.button>
            <.button
              :if={@run.status in [:stopped, :failed]}
              id="resume-run"
              variant="lime"
              size="large"
              phx-click="resume"
              phx-disable-with="Wznawiam…"
            >
              Wznów
            </.button>
            <span id="run-cost" class="ml-auto font-mono text-xs text-on-app-muted">
              Koszt API: {Polish.usd(@cost)}
            </span>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Research.get_run(socket.assigns.current_scope, id) do
      %Run{} = run ->
        if connected?(socket), do: Research.subscribe(run)

        {:ok,
         socket
         |> assign(progress: nil)
         |> stream_configure(:checked_phrases, dom_id: &"checked-phrase-#{&1.keyword_id}")
         |> stream(:checked_phrases, [])
         |> assign_run(run)}

      nil ->
        {:ok, redirect_not_found(socket)}
    end
  end

  @impl true
  def handle_info({:run_updated, _run_id}, socket) do
    {:noreply, reload_run(socket)}
  end

  def handle_info({:run_progress, _run_id, %{step: @competition_step} = progress}, socket) do
    entry = Map.take(progress, [:keyword_id, :phrase, :holders, :verdict])
    %{run: run} = socket.assigns

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> stream_delete(:checked_phrases, entry)
     |> stream_insert(:checked_phrases, entry, at: 0, limit: @checked_phrases_limit)
     |> assign_run(run)}
  end

  def handle_info({:run_progress, _run_id, _other_step_progress}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop", _params, socket) do
    socket.assigns.current_scope
    |> Research.stop_run(socket.assigns.run.id)
    |> after_run_action(socket, "Research już nie trwa.")
  end

  def handle_event("resume", _params, socket) do
    socket.assigns.current_scope
    |> Research.resume_run(socket.assigns.run.id)
    |> after_run_action(socket, "Tego researchu nie da się teraz wznowić.")
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true

  defp step_status(%{status: :done} = assigns) do
    ~H"""
    <span id={@id} class="flex flex-none items-center gap-1.5 font-mono text-[11px] text-accent">
      <.icon name="hero-check-mini" class="size-[13px]" />{RunDisplay.step_status_label(@status)}
    </span>
    """
  end

  defp step_status(%{status: :running} = assigns) do
    ~H"""
    <span
      id={@id}
      class="flex-none rounded-pill bg-accent px-[9px] py-[3px] font-mono text-[11px] text-ink"
    >
      {RunDisplay.step_status_label(@status)}
    </span>
    """
  end

  defp step_status(%{status: :failed} = assigns) do
    ~H"""
    <span id={@id} class="flex flex-none items-center gap-1.5 font-mono text-[11px] text-warn">
      <.icon name="hero-exclamation-triangle" class="size-[13px]" />{RunDisplay.step_status_label(
        @status
      )}
    </span>
    """
  end

  defp step_status(assigns) do
    ~H"""
    <span id={@id} class="flex-none font-mono text-[11px] text-on-app-muted">
      {RunDisplay.step_status_label(@status)}
    </span>
    """
  end

  attr :step, :map, required: true
  attr :progress, :map, default: nil
  attr :checked_phrases, :any, required: true

  defp competition_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <span class="font-mono text-[11px] text-on-app-muted">
        krok {@step.label_number} · {String.downcase(@step.name)}
      </span>
      <%= if @progress do %>
        <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
          {Competition.checked_line(@progress.checked, @progress.total)}
        </span>
        <div
          id="run-progress"
          role="progressbar"
          aria-label="Sprawdzone frazy"
          aria-valuemin="0"
          aria-valuemax={@progress.total}
          aria-valuenow={@progress.checked}
          class="h-2 overflow-hidden rounded-pill bg-app-line"
        >
          <div class="h-full bg-accent" style={"width: #{progress_percent(@progress)}%"}></div>
        </div>
      <% else %>
        <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
          Sprawdzam pierwsze frazy w Google
        </span>
      <% end %>
    </div>
    <div class="flex flex-col gap-2">
      <span class="font-mono text-[11px] uppercase tracking-[0.08em] text-on-app-muted">
        Ostatnio sprawdzone
      </span>
      <ul
        id="checked-phrases"
        phx-update="stream"
        class="m-0 flex list-none flex-col rounded-tile border border-app-line-strong bg-app-raised p-0"
      >
        <li
          id="checked-phrases-empty"
          class="hidden px-[18px] py-3.5 text-sm text-on-app-muted only:block"
        >
          Czekam na pierwsze wyniki z Google.
        </li>
        <li
          :for={{dom_id, entry} <- @checked_phrases}
          id={dom_id}
          data-verdict={entry.verdict}
          class="flex flex-wrap justify-between gap-x-4 gap-y-1.5 border-t border-app-line-strong px-[18px] py-3.5 first:border-t-0"
        >
          <span class="text-[15px] font-medium">{entry.phrase}</span>
          <span class={["text-[13px]", RunDisplay.verdict_class(entry.verdict)]}>{entry.holders}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :step, :map, default: nil

  defp step_detail(%{step: nil} = assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">Pracuję nad researchem</span>
    </div>
    """
  end

  defp step_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <span class="font-mono text-[11px] text-on-app-muted">
        krok {@step.label_number} · {String.downcase(@step.name)}
      </span>
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">{@step.name}</span>
      <p class="m-0 text-[15px] leading-normal text-on-app-2">{@step.summary}</p>
    </div>
    """
  end

  attr :run, Run, required: true
  attr :step, :map, default: nil
  attr :results_path, :string, required: true
  attr :published_url, :string, default: nil

  defp state_detail(%{run: %Run{status: :awaiting_choice}} = assigns) do
    ~H"""
    <div class="flex flex-col items-start gap-3">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">Nisze ocenione.</span>
      <p class="m-0 text-[15px] leading-normal text-on-app-2">
        Wybierz niszę, a napiszę dla niej brief i stronę.
      </p>
      <.button id="see-results" variant="lime" size="large" navigate={@results_path}>
        Zobacz wyniki <.icon name="hero-arrow-right" class="size-[18px]" />
      </.button>
    </div>
    """
  end

  defp state_detail(%{run: %Run{status: :done}} = assigns) do
    ~H"""
    <div class="flex flex-col items-start gap-3">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">Strona opublikowana.</span>
      <div class="flex flex-wrap gap-2.5">
        <.button id="see-results" variant="lime" size="large" navigate={@results_path}>
          Zobacz wyniki
        </.button>
        <.button
          :if={@published_url}
          id="open-published-page"
          variant="outline"
          size="large"
          href={@published_url}
          target="_blank"
          rel="noopener"
        >
          Otwórz stronę <.icon name="hero-arrow-top-right-on-square" class="size-[18px]" />
        </.button>
      </div>
    </div>
    """
  end

  defp state_detail(%{run: %Run{status: :failed}, step: %{status: :failed}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">
        Krok {@step.number} się nie udał.
      </span>
      <p id="run-failure-reason" class="m-0 text-[15px] leading-normal text-warn">{@step.error}</p>
      <p class="m-0 text-[15px] leading-normal text-on-app-2">
        Wznów, a zacznę od tego kroku. Gotowych kroków nie powtórzę.
      </p>
    </div>
    """
  end

  defp state_detail(%{step: %{number: _number}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">Research zatrzymany.</span>
      <p class="m-0 text-[15px] leading-normal text-on-app-2">
        Wznów, a zacznę od kroku {@step.number}. Gotowych kroków nie powtórzę.
      </p>
    </div>
    """
  end

  defp state_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <span class="text-2xl leading-tight font-bold tracking-[-0.02em]">Research zatrzymany.</span>
      <p class="m-0 text-[15px] leading-normal text-on-app-2">
        Wznów, a dokończę research. Gotowych kroków nie powtórzę.
      </p>
    </div>
    """
  end

  defp after_run_action({:ok, %Run{}}, socket, _refusal), do: {:noreply, reload_run(socket)}

  defp after_run_action({:error, _reason}, socket, refusal) do
    {:noreply, socket |> put_flash(:error, refusal) |> reload_run()}
  end

  defp reload_run(socket) do
    %{current_scope: scope, run: previous_run} = socket.assigns

    case Research.get_run(scope, previous_run.id) do
      %Run{} = run ->
        if results_just_ready?(previous_run, run) do
          path = RunDisplay.results_path(run)
          push_navigate(socket, to: path)
        else
          assign_run(socket, run)
        end

      nil ->
        redirect_not_found(socket)
    end
  end

  defp results_just_ready?(previous_run, run), do: not Run.results_ready?(previous_run) and Run.results_ready?(run)

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, @not_found_message)
    |> push_navigate(to: ~p"/app/runs")
  end

  defp assign_run(socket, run) do
    %{progress: progress} = socket.assigns
    short_description = RunDisplay.short_description(run.description)
    current_step = StatusLine.current_step(run)
    step_rows = step_rows(run, progress)

    assign(socket,
      page_title: "Research · #{short_description}",
      run: run,
      step_rows: step_rows,
      current_step: current_step && Enum.find(step_rows, &(&1.number == current_step.number)),
      detail: detail(run, current_step),
      short_description: short_description,
      context_line: RunDisplay.context_line(run),
      status_line: StatusLine.sentence(%{run: run, progress: progress}),
      cost: Research.run_cost(run),
      results_path: RunDisplay.results_path(run),
      published_url: published_url(run)
    )
  end

  defp step_rows(%Run{steps: steps}, progress) do
    steps_by_number = Map.new(steps, &{&1.number, &1})

    Enum.map(Steps.all(), fn %{number: number, key: key, name: name} ->
      step = Map.get(steps_by_number, number, %RunStep{number: number, status: :waiting})

      %{
        number: number,
        label_number: step_label_number(number),
        name: name,
        status: step.status,
        summary: step_summary(step, %{key: key, progress: progress}),
        error: step.error
      }
    end)
  end

  defp step_summary(%RunStep{status: :running, number: @competition_step}, %{
         progress: %{step: @competition_step, checked: checked, total: total}
       }) do
    Competition.checked_line(checked, total)
  end

  defp step_summary(%RunStep{result: result}, _context) when is_binary(result), do: result
  defp step_summary(_step, %{key: key}), do: Map.fetch!(@step_hints, key)

  defp detail(%Run{status: :running}, %RunStep{number: @competition_step}), do: :competition
  defp detail(%Run{status: :running}, _step), do: :step
  defp detail(_not_running, _step), do: :state

  defp published_url(%Run{steps: steps}) do
    case Enum.find(steps, &(&1.number == @publish_step)) do
      %RunStep{status: :done, output: %{"url" => url}} when is_binary(url) -> url
      _not_published -> nil
    end
  end

  defp progress_percent(%{checked: checked, total: total}) when is_integer(total) and total > 0 do
    percent = round(checked * 100 / total)
    min(percent, 100)
  end

  defp progress_percent(_progress), do: 0

  defp step_label_number(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp step_name_class(:running), do: "font-bold text-on-app"
  defp step_name_class(status) when status in [:waiting, :queued, :skipped], do: "font-medium text-on-app-2"
  defp step_name_class(_done_or_failed), do: "font-medium text-on-app"
end
