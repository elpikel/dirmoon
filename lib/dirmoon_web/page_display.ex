defmodule DirmoonWeb.PageDisplay do
  @moduledoc """
  How a Page (the record holding a Niche's Brief) reads on screen, shared by
  the brief screen (`PageLive`), the briefs list (`PagesLive`) and the
  results screen (`ResultsLive`, which starts a Brief by choosing a Niche):
  its status labels, its title, and the copy for each reason a Niche choice
  is refused.
  """

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page

  @status_labels %{
    writing: "Writing",
    ready: "Ready",
    failed: "Failed"
  }

  @choose_errors %{
    not_found: "Niche not found",
    run_not_ready: "You can't choose a niche now: the research hasn't finished scoring or is stopped",
    run_busy: "The research is still working. You can choose a niche when it finishes the current step",
    brief_in_progress: "A brief for another niche is being written",
    not_choosable: "This niche can no longer be chosen"
  }

  @doc """
  The label of a page's status ("Writing", "Ready"…), one for each of
  `Page.statuses/0`.
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @doc """
  The message for a reason `Dirmoon.Niches.choose/2` refused a Niche.
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
  The day the page was created ("3 Nov 2026").
  """
  def date(%Page{inserted_at: inserted_at}), do: Calendar.strftime(inserted_at, "%-d %b %Y")

  defp present?(text), do: is_binary(text) and String.trim(text) != ""
end
