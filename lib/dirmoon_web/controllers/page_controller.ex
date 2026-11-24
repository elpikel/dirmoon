defmodule DirmoonWeb.PageController do
  use DirmoonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
