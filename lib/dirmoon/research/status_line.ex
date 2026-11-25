defmodule Dirmoon.Research.StatusLine do
  @moduledoc """
  The status sentence of a Research Run: one first-person line saying
  what dirmoon is doing or found, built only from the run's state (its status,
  its Steps and the latest progress), never by the LLM. See
  `docs/design/README.md` section 8.2.

  Every sentence lives in `@sentences`, keyed by run status, or by
  `{:running, step_key}` (a key from `Dirmoon.Research.Steps`) for a running
  run. Templates fill `%{step}`,
  `%{reason}`, `%{checked}` and `%{total}`.
  """

  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  @competition_step Steps.number!(:competition)

  @sentences %{
    {:running, :seeds} => "I'm turning the description into seed phrases and customer questions.",
    {:running, :expansion} => "I'm expanding the seed phrases into what people really type.",
    {:running, :volumes} => "I'm checking the volume and CPC of every phrase.",
    {:running, :filter_and_group} => "I'm dropping phrases outside the business and grouping the rest into niches.",
    {:running, :competition} => "I'm checking who ranks for the best phrases. After step 7 you choose a niche.",
    {:running, :current_positions} => "I'm checking which phrases the site already shows up for.",
    {:running, :scoring} => "I'm scoring the niches by volume, CPC and how weak the competition is.",
    {:running, :brief} => "I'm writing the brief for the chosen niche.",
    :competition_progress =>
      "I'm checking who ranks for the best phrases (%{checked} of %{total}). After step 7 you choose a niche.",
    :running => "I'm working on the research.",
    :awaiting_choice => "The niches are scored. Choose one and I'll write a brief for it.",
    :stopped => "I stopped the research at step %{step}. You can resume it.",
    :stopped_after_last_step => "I stopped the research. You can resume it.",
    :failed => "Step %{step} failed: %{reason}.",
    :failed_without_step => "The research failed."
  }

  @doc """
  The status sentence for a run with its Steps loaded, and the latest
  progress message of its running Step (`nil` when there is none).
  """
  def sentence(%{run: %Run{} = run, progress: progress}) do
    step = current_step(run)

    run
    |> sentence_key(step, progress)
    |> fill()
  end

  @doc """
  The Step the run is at: one at work or queued, else a failed one, else the
  first of Steps 1–7 that isn't done or skipped; `nil` when there is none.
  """
  def current_step(%Run{steps: steps}) when is_list(steps) do
    Enum.find(steps, &RunStep.in_progress?/1) ||
      Enum.find(steps, &(&1.status == :failed)) ||
      Enum.find(steps, &(Steps.auto_chained?(&1.number) and not RunStep.finished?(&1)))
  end

  defp sentence_key(%Run{status: :running}, %RunStep{number: @competition_step}, %{
         step: @competition_step,
         checked: checked,
         total: total
       }) do
    {:competition_progress, %{checked: checked, total: total}}
  end

  defp sentence_key(%Run{status: :running}, %RunStep{number: number}, _progress) do
    %{key: step_key} = Steps.get!(number)
    {{:running, step_key}, %{}}
  end

  defp sentence_key(%Run{status: :running}, nil, _progress), do: {:running, %{}}
  defp sentence_key(%Run{status: :stopped}, %RunStep{number: number}, _progress), do: {:stopped, %{step: number}}
  defp sentence_key(%Run{status: :stopped}, nil, _progress), do: {:stopped_after_last_step, %{}}

  defp sentence_key(%Run{status: :failed}, %RunStep{status: :failed, number: number, error: error}, _progress) do
    {:failed, %{step: number, reason: readable_reason(error)}}
  end

  defp sentence_key(%Run{status: :failed}, _not_failed_step, _progress), do: {:failed_without_step, %{}}
  defp sentence_key(%Run{status: status}, _step, _progress), do: {status, %{}}

  defp fill({key, bindings}) do
    template = Map.fetch!(@sentences, key)

    Enum.reduce(bindings, template, fn {name, value}, sentence ->
      text = to_string(value)
      String.replace(sentence, "%{#{name}}", text)
    end)
  end

  defp readable_reason(nil), do: "unknown error"

  defp readable_reason(error) do
    error
    |> String.trim()
    |> String.trim_trailing(".")
  end
end
