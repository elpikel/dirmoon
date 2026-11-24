defmodule DirmoonWeb.PageController do
  use DirmoonWeb, :controller

  alias DirmoonWeb.PageHTML

  def home(conn, _params) do
    render(conn, :home, sign_up_forms: PageHTML.sign_up_forms())
  end
end
