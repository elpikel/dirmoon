defmodule DirmoonWeb.RunDisplay do
  @moduledoc """
  How a Research Run reads on screen, shared by the run screen (`RunLive`),
  the runs list (`RunsLive`), the results (`ResultsLive`) and its CSV
  export: its short description, Mode, location and status labels, the
  labels of its Steps' statuses and of competition verdicts, its date, and
  the paths to the run, its results and a Niche's page.
  """
  use DirmoonWeb, :verified_routes

  alias Dirmoon.Pages.Page
  alias Dirmoon.Research.Run

  @short_description_length 48

  @status_labels %{
    running: "In progress",
    stopped: "Stopped",
    failed: "Failed",
    awaiting_choice: "Awaiting choice"
  }

  @mode_labels %{
    new_idea: "New idea",
    existing_site: "Existing site"
  }

  @step_status_labels %{
    done: "Done",
    running: "In progress",
    waiting: "Waiting",
    queued: "Waiting",
    skipped: "Skipped",
    failed: "Failed"
  }

  @verdict_labels %{
    weak: "Weak",
    medium: "Medium",
    strong: "Strong"
  }

  @doc """
  The description's first sentence, cut at a word boundary with an ellipsis
  when it runs longer than #{@short_description_length} characters.
  """
  def short_description(description) when is_binary(description) do
    first_sentence =
      description
      |> String.split(~r/[.!?\n]/u, parts: 2)
      |> hd()
      |> String.trim()

    if String.length(first_sentence) > @short_description_length do
      first_sentence
      |> String.slice(0, @short_description_length)
      |> String.replace(~r/\s+\S*$/u, "")
      |> Kernel.<>("…")
    else
      first_sentence
    end
  end

  @doc """
  The run's country name, and its city when it has one ("Poland · Toruń").
  """
  def location(%Run{city: city} = run) do
    [country_name(run), city]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  @doc """
  The name of the run's country ("Poland"), from `Run.locations/0`.
  """
  def country_name(%Run{country_code: country_code}) do
    country_code
    |> run_location()
    |> Map.fetch!(:country_name)
  end

  @doc """
  The run's country and language ("Poland · Polish").
  """
  def country_and_language(%Run{country_code: country_code}) do
    %{country_name: country_name, language_name: language_name} = run_location(country_code)
    "#{country_name} · #{language_name}"
  end

  @doc """
  The eyebrow line of a run's screens: its short description, country and
  city ("Boat rental · Poland · Toruń").
  """
  def context_line(%Run{description: description} = run) do
    [short_description(description), location(run)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" · ")
  end

  @doc """
  The label of a run's status ("In progress", "Awaiting choice"…), one for
  each of `Run.statuses/0`.
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @doc """
  The name of a run's Mode ("New idea", "Existing site").
  """
  def mode_label(mode), do: Map.fetch!(@mode_labels, mode)

  @doc """
  The label of a Step's status ("Done", "In progress", "Waiting"…), one
  for each of `RunStep.statuses/0`; a queued Step reads as waiting.
  """
  def step_status_label(status), do: Map.fetch!(@step_status_labels, status)

  @doc """
  The word for a competition verdict ("Weak", "Medium", "Strong"),
  one for each of `SerpAssessment.verdicts/0`.
  """
  def verdict_label(verdict), do: Map.fetch!(@verdict_labels, verdict)

  @doc """
  The text colour of a competition verdict in the app: weak in the accent,
  strong in the warning colour, medium in the secondary text colour, an
  unchecked one (nil) muted.
  """
  def verdict_class(:weak), do: "text-accent"
  def verdict_class(:medium), do: "text-on-app-2"
  def verdict_class(:strong), do: "text-warn"
  def verdict_class(nil), do: "text-on-app-muted"

  @doc """
  The day the run started ("3 Nov 2026").
  """
  def date(%Run{inserted_at: inserted_at}), do: Calendar.strftime(inserted_at, "%-d %b %Y")

  @doc """
  Where a run leads: its results once they are ready
  (`Run.results_ready?/1`), else the run screen. Needs the run's Steps.
  """
  def path(%Run{} = run) do
    if Run.results_ready?(run), do: results_path(run), else: ~p"/app/runs/#{run}"
  end

  @doc """
  The path to the run's results screen.
  """
  def results_path(%Run{} = run), do: ~p"/app/runs/#{run}/results"

  @doc """
  The path to a page's screen.
  """
  def page_path(%Page{} = page), do: ~p"/app/pages/#{page}"

  defp run_location(country_code) do
    locations = Run.locations()
    Enum.find(locations, %{country_name: country_code, language_name: ""}, &(&1.country_code == country_code))
  end
end
