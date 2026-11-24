defmodule Dirmoon.Phrases.Expansion do
  @moduledoc """
  Step 2: turns the run's Seeds (Step 1's output) into the Phrases people
  really type, through the keyword API, in batches of at most
  `Dirmoon.DataForSEO.max_seeds/0` Seeds. Every batch goes through the run's
  ledger (`Dirmoon.Phrases.LedgerRows`), so a retry or a resume never buys a
  batch twice.
  """

  alias Dirmoon.DataForSEO
  alias Dirmoon.Phrases
  alias Dirmoon.Phrases.LedgerRows
  alias Dirmoon.Polish
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.Steps

  @seeds_step_number Steps.number!(:seeds)
  @no_seeds_error "Brak fraz startowych z kroku 1"
  @no_phrases_error "Brak fraz dla tych załążków"
  @phrase_forms %{one: "realna fraza", few: "realne frazy", many: "realnych fraz"}

  @doc """
  Expands the run's Seeds and stores the Phrases with their country Volumes.

  Returns `{:ok, %{result: "412 realnych fraz", output: %{"phrases" => 412, "requests" => 2}}}`,
  `{:error, "Brak fraz startowych z kroku 1"}`, `{:error, "Brak fraz dla tych załążków"}`
  or the keyword API's `{:error, reason}` (batches fetched before it stay in
  the ledger).
  """
  def expand(%Run{} = run) do
    with {:ok, seeds} <- seeds(run),
         batches = Enum.chunk_every(seeds, DataForSEO.max_seeds()),
         {:ok, rows} <- fetch_rows(run, batches),
         {:ok, count} when count > 0 <- Phrases.store_expansion(run, rows) do
      {:ok, %{result: result_line(count), output: %{"phrases" => count, "requests" => length(batches)}}}
    else
      {:ok, 0} -> {:error, @no_phrases_error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp seeds(run) do
    case Research.step_output(run, @seeds_step_number) do
      {:ok, %{"seeds" => [_seed | _more] = seeds}} -> {:ok, seeds}
      _missing_or_empty -> {:error, @no_seeds_error}
    end
  end

  defp fetch_rows(run, batches) do
    batches
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, reversed_batch_rows} ->
      case fetch_batch(run, batch) do
        {:ok, batch_rows} -> {:cont, {:ok, [batch_rows | reversed_batch_rows]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed_batch_rows} -> {:ok, reversed_batch_rows |> Enum.reverse() |> Enum.concat()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_batch(run, batch) do
    request = %{seeds: batch, location_code: run.location_code, language_code: run.language_code}

    with {:ok, %{rows: rows}} <-
           LedgerRows.fetch(run, %{operation: "keyword_ideas", request: request}, &DataForSEO.keyword_ideas/1) do
      {:ok, rows}
    end
  end

  defp result_line(count), do: "#{count} #{Polish.plural(count, @phrase_forms)}"
end
