defmodule DirmoonWeb.Controllers.PageFile.ShowTest do
  use DirmoonWeb.ConnCase, async: true

  test "the content file downloads as one html file named after the slug", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    run = insert(:run, account: scope.account, status: :done)
    page = insert(:page, run: run, brief: build(:brief, slug: "hotel-dla-psa", h1: "Hotel dla psa"))

    conn = get(conn, ~p"/app/pages/#{page.id}/file")

    assert response(conn, 200) =~ "Hotel dla psa"
    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename="hotel-dla-psa.html")
  end

  test "the downloaded page is self-contained, without an external stylesheet or script", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account))

    body = conn |> get(~p"/app/pages/#{page.id}/file") |> response(200)

    document = LazyHTML.from_document(body)
    assert document |> LazyHTML.query("link[rel=stylesheet]") |> Enum.empty?()
    assert document |> LazyHTML.query("script[src]") |> Enum.empty?()
    assert document |> LazyHTML.query("style") |> Enum.count() >= 1
  end

  test "a published page can still be downloaded", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :published)

    assert conn |> get(~p"/app/pages/#{page.id}/file") |> response(200) =~ "<!DOCTYPE html>"
  end

  test "another Account's page is not found", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run))

    conn = get(conn, ~p"/app/pages/#{page.id}/file")

    assert response(conn, 404) == "Not Found"
  end

  test "a malformed page id is not found", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert conn |> get(~p"/app/pages/not-an-id/file") |> response(404) == "Not Found"
  end

  test "a page whose brief is still being written is not found", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    page = insert(:page, run: insert(:run, account: scope.account), status: :writing, brief: nil)

    assert conn |> get(~p"/app/pages/#{page.id}/file") |> response(404) == "Not Found"
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    page = insert(:page, run: insert(:run))

    conn = get(conn, ~p"/app/pages/#{page.id}/file")

    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
