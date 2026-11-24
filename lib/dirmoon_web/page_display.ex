defmodule DirmoonWeb.PageDisplay do
  @moduledoc """
  How a Produced Page reads on screen, shared by the page screen (`PageLive`),
  the pages list (`PagesLive`) and the results screen (`ResultsLive`, which
  starts a page by choosing a Niche): its status labels and headline, its
  title, its address before it is published, and the Polish copy for each
  reason a Niche choice is refused.
  """

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page

  @domain_placeholder "[TWOJA-DOMENA]"

  @status_labels %{
    writing: "Piszę",
    ready: "Gotowa",
    publishing: "Publikuję",
    published: "Opublikowana",
    failed: "Błąd"
  }

  @headlines %{
    writing: %{lead: "Piszę", underline: "brief."},
    ready: %{lead: "Brief gotowy.", underline: "Strona też."},
    publishing: %{lead: "Publikuję", underline: "stronę."},
    published: %{lead: "Brief gotowy.", underline: "Strona też."},
    failed: %{lead: "Brief się", underline: "nie udał."}
  }

  @stopped_run_headlines %{
    writing: %{lead: "Brief", underline: "czeka."},
    publishing: %{lead: "Publikacja", underline: "czeka."}
  }

  @choose_errors %{
    not_found: "Nie znaleziono niszy",
    run_not_ready: "Teraz nie wybierzesz niszy: research nie skończył oceniania albo jest zatrzymany",
    run_busy: "Research jeszcze pracuje. Wybierzesz niszę, gdy skończy bieżący krok",
    brief_in_progress: "Brief dla innej niszy jest w trakcie pisania",
    not_choosable: "Tej niszy nie można już wybrać"
  }

  @doc """
  The Polish label of a page's status ("Piszę", "Gotowa"…), one for each of
  `Page.statuses/0`.
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @doc """
  The page screen's headline for a page's status and whether its run is
  stopped: `%{lead:, underline:}`, the underline being the phrase drawn over
  the lime line. Work waiting on a stopped run reads as waiting ("Brief
  czeka."), matching the panel.
  """
  def headline(%{status: status, run_stopped?: true}) when is_map_key(@stopped_run_headlines, status) do
    Map.fetch!(@stopped_run_headlines, status)
  end

  def headline(%{status: status, run_stopped?: _run_stopped?}), do: Map.fetch!(@headlines, status)

  @doc """
  The Polish message for a reason `Dirmoon.Niches.choose/2` refused a Niche.
  """
  def choose_error(reason), do: Map.fetch!(@choose_errors, reason)

  @doc """
  What a page is called: its Brief's title, else its H1, else (while the Brief
  is being written) its Niche's name.
  """
  def title(%Page{brief: %Brief{title: title, h1: h1}, niche: niche}) do
    Enum.find([title, h1], niche.name, &present?/1)
  end

  def title(%Page{brief: nil, niche: niche}), do: niche.name

  @doc """
  Where a page will live before it is published: the domain Placeholder and
  its slug ("[TWOJA-DOMENA]/pierwszy-raz-kamperem").
  """
  def address(slug) do
    if present?(slug), do: "#{@domain_placeholder}/#{slug}", else: "#{@domain_placeholder}/"
  end

  @doc """
  The domain Placeholder shown before the page's slug.
  """
  def domain_placeholder, do: @domain_placeholder

  @doc """
  The day the page was created, as Polish readers write it ("03.11.2026").
  """
  def date(%Page{inserted_at: inserted_at}), do: Calendar.strftime(inserted_at, "%d.%m.%Y")

  defp present?(text), do: is_binary(text) and String.trim(text) != ""
end
