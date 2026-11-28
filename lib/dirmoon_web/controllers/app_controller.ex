defmodule DirmoonWeb.AppController do
  @moduledoc """
  The signed-in app's root, `/app`, where sign-in lands: it sends a User
  with no research left to the plan screen, and everyone else to the new
  research screen.
  """
  use DirmoonWeb, :controller

  alias Dirmoon.Billing

  def index(conn, _params) do
    case Billing.researches_left(conn.assigns.current_scope) do
      0 -> redirect(conn, to: ~p"/app/billing")
      _some_or_unlimited -> redirect(conn, to: ~p"/app/research/new")
    end
  end
end
