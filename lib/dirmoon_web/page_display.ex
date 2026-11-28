defmodule DirmoonWeb.PageDisplay do
  @moduledoc """
  How a Page (the record holding a Niche's Brief) reads on screen, shared by
  the brief screen (`PageLive`), the briefs list (`PagesLive`) and the
  results screen (`ResultsLive`, which starts a Brief by choosing a Niche):
  its status labels, its title, and the copy for each reason a Niche choice
  is refused.
  """

  alias Dirmoon.Billing
  alias Dirmoon.Format
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page

  @status_labels %{
    writing: "Writing",
    ready: "Ready",
    failed: "Failed"
  }

  @choose_errors %{
    not_found: "Topic not found",
    run_not_ready: "You can't choose a topic now: the research hasn't finished rating them or is stopped",
    run_busy: "The research is still working. You can choose a topic when it finishes the current step",
    brief_in_progress: "I'm still writing the brief for another topic",
    not_choosable: "This topic can no longer be chosen"
  }

  @used_brief_forms %{one: "brief is", other: "briefs are"}

  @doc """
  The label of a page's status ("Writing", "Ready"…), one for each of
  `Page.statuses/0`.
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @doc """
  The message for a reason `Dirmoon.Niches.choose/2` refused a Niche.
  """
  def choose_error(:brief_limit_reached) do
    briefs = Billing.offer().briefs_per_research
    "This research's #{briefs} #{Format.plural(briefs, @used_brief_forms)} used, so I can't write another"
  end

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
