defmodule Dirmoon.Research.StatusLine do
  @moduledoc """
  The status sentence of a Research Run: one first-person Polish line saying
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
    {:running, :seeds} => "Zamieniam opis na frazy startowe i pytania klientów.",
    {:running, :expansion} => "Rozwijam frazy startowe w to, co ludzie naprawdę wpisują.",
    {:running, :volumes} => "Sprawdzam wolumeny i CPC dla każdej frazy.",
    {:running, :filter_and_group} => "Odsiewam frazy spoza oferty i grupuję resztę w nisze.",
    {:running, :competition} => "Sprawdzam, kto odpowiada na najlepsze frazy. Po kroku 7 wybierasz niszę.",
    {:running, :current_positions} => "Sprawdzam, na które frazy strona już jest widoczna.",
    {:running, :scoring} => "Oceniam nisze po wolumenie, CPC i słabości konkurencji.",
    {:running, :brief_and_content} => "Piszę brief i treść dla wybranej niszy.",
    :competition_progress =>
      "Sprawdzam, kto odpowiada na najlepsze frazy (%{checked} z %{total}). Po kroku 7 wybierasz niszę.",
    :running => "Pracuję nad researchem.",
    :awaiting_choice => "Nisze ocenione. Wybierz jedną, a napiszę dla niej stronę.",
    :stopped => "Zatrzymałem research na kroku %{step}. Możesz go wznowić.",
    :stopped_after_last_step => "Zatrzymałem research. Możesz go wznowić.",
    :failed => "Krok %{step} się nie udał: %{reason}.",
    :failed_without_step => "Research się nie udał."
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

  defp readable_reason(nil), do: "nieznany błąd"

  defp readable_reason(error) do
    error
    |> String.trim()
    |> String.trim_trailing(".")
  end
end
