defmodule DirmoonWeb.ConnCase do
  @moduledoc """
  Test case for tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use DirmoonWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use DirmoonWeb, :verified_routes

      import Dirmoon.Factory
      import DirmoonWeb.ConnCase
      import Phoenix.ConnTest

      # Import conveniences for testing with connections
      import Plug.Conn

      # The default endpoint for testing
      @endpoint DirmoonWeb.Endpoint
    end
  end

  setup tags do
    Dirmoon.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Inserts a confirmed user with an Account and logs them into the conn.

      %{conn: conn, user: user, scope: scope} = register_and_log_in_user(%{conn: conn})

  Pass `:token_authenticated_at` to backdate the sign-in (for sudo mode).
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Dirmoon.Factory.insert(:user)
    scope = Dirmoon.Accounts.scope_for_user(user)
    opts = context |> Map.take([:token_authenticated_at]) |> Enum.to_list()

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Dirmoon.Accounts.generate_user_session_token(user)

    if authenticated_at = opts[:token_authenticated_at] do
      Dirmoon.AccountsHelpers.override_token_authenticated_at(token, authenticated_at)
    end

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
