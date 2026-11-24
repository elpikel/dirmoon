defmodule DirmoonWeb.PageFileController do
  use DirmoonWeb, :controller

  alias Dirmoon.Pages

  def show(conn, %{"id" => page_id}) do
    case Pages.content_file(conn.assigns.current_scope, page_id) do
      {:ok, %{filename: filename, html: html}} ->
        send_download(conn, {:binary, html}, filename: filename, content_type: "text/html", charset: "utf-8")

      {:error, _not_found_or_not_ready} ->
        conn
        |> put_status(:not_found)
        |> put_root_layout(false)
        |> put_view(html: DirmoonWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
