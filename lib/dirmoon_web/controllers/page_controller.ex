defmodule DirmoonWeb.PageController do
  use DirmoonWeb, :controller

  alias DirmoonWeb.PageHTML

  def home(conn, _params) do
    render(conn, :home, PageHTML.landing_assigns(PageHTML.sign_up_forms()))
  end
end
