defmodule DirmoonWeb.AppController do
  @moduledoc """
  The signed-in app's root, `/app`, where sign-in lands: it sends the User on
  to the new research screen.
  """
  use DirmoonWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/app/research/new")
  end
end
