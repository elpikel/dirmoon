defmodule Dirmoon.Pages do
  @moduledoc """
  Pages: the record that holds a Chosen Niche's Brief, one per chosen
  Niche, with the Brief Step 8 writes and the User edits. dirmoon builds no
  page from it: the owner hands the Brief to whoever builds their site.

  Every function that reads or changes a page by id takes the `Scope` and
  only sees the Scope's Account's pages (ADR-0001); a foreign id is not
  found. Functions that take a `%Run{}` or `%Niche{}` expect one already
  resolved through the Scope (or a pipeline job).

  Subscribers to a page (`subscribe/1`) receive `{:page_updated, page_id}`
  when its status or Brief changes.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Repo
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep

  @list_limit 50

  @doc """
  Creates the `:writing` page for a Niche of the run, in the run's Account.
  Called inside `Dirmoon.Niches.choose/2`'s transaction; the caller
  broadcasts once it commits.
  """
  def create_for_niche(%Run{id: run_id, account_id: account_id}, %Niche{id: niche_id, run_id: run_id}) do
    Repo.insert(%Page{account_id: account_id, run_id: run_id, cluster_id: niche_id, status: :writing})
  end

  @doc """
  Sets a `:failed` page back to `:writing`, clearing its error, so Step 8
  writes it again.
  """
  def restart_writing(%Page{status: :failed} = page) do
    page
    |> Ecto.Changeset.change(status: :writing, error: nil)
    |> Repo.update()
  end

  @doc """
  The Niche's page, or nil.
  """
  def page_for_niche(%Niche{id: niche_id}) do
    Repo.get_by(Page, cluster_id: niche_id)
  end

  @doc """
  The run's page Step 8 is writing, with its Niche, or nil. A run has at
  most one.
  """
  def writing_page_for_run(%Run{id: run_id}) do
    Page
    |> from(as: :page)
    |> where([page: page], page.run_id == ^run_id and page.status == ^:writing)
    |> preload(:niche)
    |> Repo.one()
  end

  @doc """
  Stores the Brief Step 8 wrote (string- or atom-keyed params, validated by
  `Brief.changeset/2`) and marks the page `:ready`.

  Returns `{:ok, page}` or `{:error, changeset}`.
  """
  def store_brief(%Page{} = page, brief_params) do
    page
    |> Page.brief_changeset(brief_params)
    |> Ecto.Changeset.change(status: :ready, error: nil)
    |> Repo.update()
    |> tap(&broadcast_updated/1)
  end

  @doc """
  Marks the run's `:writing` page `:failed` with `reason` once Step 8 gave
  up. Called by the Step 8 worker with the job's run id, never with params.
  """
  def fail_writing_pages(run_id, reason) when is_integer(run_id) and is_binary(reason) do
    {_count, page_ids} =
      Page
      |> from(as: :page)
      |> where([page: page], page.run_id == ^run_id and page.status == ^:writing)
      |> select([page: page], page.id)
      |> Repo.update_all(set: [status: :failed, error: reason, updated_at: DateTime.utc_now(:second)])

    Enum.each(page_ids, &broadcast_page_updated/1)
  end

  @doc """
  The Scope's Account's page with the given id, its Niche and its run (with
  the run's Steps in order, so `Run.choosable?/1` can be asked of it)
  preloaded, or nil.
  """
  def get_page(%Scope{} = scope, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, page_id} ->
        scope
        |> account_pages_query()
        |> where([page: page], page.id == ^page_id)
        |> preload([:niche, run: [steps: ^RunStep.ordered_by_number()]])
        |> Repo.one()

      :error ->
        nil
    end
  end

  @doc """
  The Scope's Account's latest pages, newest first, with their Niches and
  runs.
  """
  def list_pages(%Scope{} = scope) do
    scope
    |> account_pages_query()
    |> order_by([page: page], desc: page.inserted_at, desc: page.id)
    |> limit(@list_limit)
    |> preload([:niche, :run])
    |> Repo.all()
  end

  @doc """
  A changeset of the page's Brief, for the form.
  """
  def change_brief(%Page{brief: brief}, params \\ %{}) do
    Brief.changeset(brief || %Brief{}, params)
  end

  @doc """
  Saves the User's edit of a page's Brief. The User's own values are kept as
  typed (only LLM output is scrubbed of invented contact data).

  Returns `{:ok, page}`, `{:error, brief_changeset}` when the Brief is
  invalid, `{:error, :not_found}` for an id outside the Scope's Account and
  `{:error, :not_editable}` for a page without a written Brief.
  """
  def update_brief(%Scope{} = scope, page_id, params) do
    with {:ok, page} <- fetch_page(scope, page_id),
         :ok <- ensure_editable(page),
         brief_changeset = change_brief(page, params),
         {:ok, _brief} <- Ecto.Changeset.apply_action(brief_changeset, :update),
         {:ok, updated_page} <- page |> Page.brief_changeset(params) |> Repo.update() do
      broadcast_page_updated(updated_page)
      {:ok, updated_page}
    end
  end

  @doc """
  Subscribes the caller to a page's updates. Takes a page already resolved
  through the Scope (`get_page/2`).
  """
  def subscribe(%Page{} = page) do
    Phoenix.PubSub.subscribe(Dirmoon.PubSub, topic(page))
  end

  @doc """
  Tells subscribers that the page's status or Brief changed:
  `{:page_updated, page_id}`.
  """
  def broadcast_page_updated(page_or_id) do
    Phoenix.PubSub.broadcast(Dirmoon.PubSub, topic(page_or_id), {:page_updated, page_id(page_or_id)})
  end

  defp account_pages_query(%Scope{account: account}) do
    Page
    |> from(as: :page)
    |> where([page: page], page.account_id == ^account.id)
  end

  defp fetch_page(scope, id) do
    case get_page(scope, id) do
      %Page{} = page -> {:ok, page}
      nil -> {:error, :not_found}
    end
  end

  defp ensure_editable(%Page{status: :ready}), do: :ok
  defp ensure_editable(%Page{}), do: {:error, :not_editable}

  defp broadcast_updated({:ok, page}), do: broadcast_page_updated(page)
  defp broadcast_updated({:error, _changeset}), do: :ok

  defp topic(page_or_id), do: "page:#{page_id(page_or_id)}"

  defp page_id(%Page{id: page_id}), do: page_id
  defp page_id(page_id), do: page_id
end
