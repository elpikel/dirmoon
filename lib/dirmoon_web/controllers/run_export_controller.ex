defmodule DirmoonWeb.RunExportController do
  @moduledoc """
  "Export CSV" on the results screen: every Phrase of a run, kept and
  rejected, as one UTF-8 CSV file (with a byte order mark, so spreadsheets
  read letters such as Polish ones). Cells are quoted when needed, and a cell a
  spreadsheet would run as a formula gets a leading apostrophe.
  """
  use DirmoonWeb, :controller

  alias Dirmoon.Phrases
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias DirmoonWeb.RunDisplay

  @byte_order_mark <<0xEF, 0xBB, 0xBF>>
  @header ~w(phrase niche country_volume city_volume cpc currency top10 verdict position quick_win rejected reason)
  @formula_triggers ["=", "+", "-", "@", "\t", "\r"]

  def show(conn, %{"id" => run_id}) do
    case Research.get_run(conn.assigns.current_scope, run_id) do
      %Run{} = run ->
        rows = run |> Phrases.export_rows() |> Enum.map(&cells/1)
        csv = to_csv([@header | rows])

        send_download(conn, {:binary, csv},
          filename: "research-#{run.id}.csv",
          content_type: "text/csv",
          charset: "utf-8"
        )

      nil ->
        conn
        |> put_status(:not_found)
        |> put_root_layout(false)
        |> put_view(html: DirmoonWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp cells(row) do
    [
      row.phrase,
      row.niche,
      row.country_volume,
      row.city_volume,
      row.cpc,
      row.currency,
      row.holders,
      row.verdict && RunDisplay.verdict_label(row.verdict),
      row.current_position,
      yes_no(row.quick_win?),
      yes_no(row.rejected?),
      row.rejection_reason
    ]
  end

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp to_csv(rows) do
    lines = Enum.map_join(rows, &line/1)
    @byte_order_mark <> lines
  end

  defp line(values) do
    cells = Enum.map_join(values, ",", &cell/1)
    cells <> "\r\n"
  end

  defp cell(nil), do: ""
  defp cell(%Decimal{} = number), do: Decimal.to_string(number, :normal)
  defp cell(number) when is_integer(number), do: Integer.to_string(number)

  defp cell(text) when is_binary(text) do
    text
    |> neutralise_formula()
    |> quote_when_needed()
  end

  defp neutralise_formula(text) do
    if String.starts_with?(text, @formula_triggers), do: "'" <> text, else: text
  end

  defp quote_when_needed(text) do
    if String.contains?(text, [",", "\"", "\n", "\r"]) do
      escaped = String.replace(text, "\"", "\"\"")
      "\"" <> escaped <> "\""
    else
      text
    end
  end
end
