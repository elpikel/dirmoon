defmodule Dirmoon.DataCase do
  @moduledoc """
  Test case for tests requiring access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Dirmoon.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Dirmoon.DataCase
      import Dirmoon.Factory
      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      alias Dirmoon.Repo
    end
  end

  setup tags do
    Dirmoon.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Dirmoon.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  The JSON text Postgres holds in the jsonb `column` of each `table` row
  matching `where` (an SQL condition on `$1`), decoded, in row order. Reading
  the text, not the Ecto field, shows exactly what was written.

      stored_json(%{table: "keyword_metrics", column: "raw", where: "keyword_id = $1", value: phrase.id})
  """
  def stored_json(%{table: table, column: column, where: where, value: value}) do
    %Postgrex.Result{rows: rows} =
      Dirmoon.Repo.query!("SELECT #{column}::text FROM #{table} WHERE #{where} ORDER BY id", [value])

    Enum.map(rows, fn [json] -> Jason.decode!(json) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
