defmodule Dirmoon.Pages do
  @moduledoc """
  Pages: one per chosen Niche, with the Brief Step 8 writes and the
  User edits.

  Every function that reads or changes a page by id takes the `Scope` and
  only sees the Scope's Account's pages (ADR-0001); a foreign id is not
  found. Functions that take a `%Run{}` or `%Niche{}` expect one already
  resolved through the Scope (or a pipeline job).

  Subscribers to a page (`subscribe/1`) receive `{:page_updated, page_id}`
  when its status or Brief changes.

  Step 9 publishes a page (`publish/2`, then `Dirmoon.Pages.Publisher`);
  `content_file/2` hands out the same HTML as a download.
  """

  import Ecto.Query

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Pages.Template
  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Pipeline
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  @list_limit 50
  @publish_step Steps.number!(:publish)
  @content_filename_format ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @fallback_content_filename "strona"

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
  The User publishes a page (Step 9). In one transaction, with the run
  locked: the page is marked `:publishing` and Step 9 is enqueued
  (`Dirmoon.Research.Pipeline.start_step/2`); subscribers to the page and
  to the run are told once it commits. Both Modes can publish.

  The run must be idle (`Dirmoon.Research.idle?/1`): not running and with
  no Step 8 or 9 queued or running. A stopped run whose Step 8 or 9 is still
  queued is resumed first; a Step 9 started underneath another Step would
  leave one of them without a job. As no Step 9 job will finish a
  `:publishing` page of an idle run (its worker stopped between failing
  Step 9 and putting the page back), such a page is put back to `:ready` or
  `:published` first. The page must be `:ready` or `:published` with a
  valid Brief.

  Returns `{:ok, page}` or `{:error, :not_found | :run_busy | :not_publishable}`.
  """
  def publish(%Scope{} = scope, page_id) do
    with {:ok, page} <- fetch_page(scope, page_id),
         {:ok, %{page: publishing_page, run: run, released_page_ids: released_page_ids}} <-
           Repo.transact(fn -> publish_in_locked_run(page) end) do
      Enum.each(released_page_ids, &broadcast_page_updated/1)
      broadcast_page_updated(publishing_page)
      Research.broadcast_run_updated(run)
      {:ok, publishing_page}
    end
  end

  @doc """
  The run's page Step 9 is publishing, with its run, or nil.
  """
  def publishing_page_for_run(%Run{id: run_id}) do
    Page
    |> from(as: :page)
    |> where([page: page], page.run_id == ^run_id and page.status == ^:publishing)
    |> order_by([page: page], asc: page.id)
    |> limit(1)
    |> preload(:run)
    |> Repo.one()
  end

  @doc """
  Stores the hosting site Step 9 created for the page, before it deploys,
  so a retry deploys to that site instead of creating another one.
  """
  def store_hosting_site(%Page{} = page, site_id) when is_binary(site_id) do
    page
    |> Ecto.Changeset.change(hosting_site_id: site_id)
    |> Repo.update()
  end

  @doc """
  Stores where Step 9 deployed the page and marks it `:published`.
  """
  def store_published(%Page{} = page, %{url: url}) when is_binary(url) do
    page
    |> Ecto.Changeset.change(status: :published, published_url: url, error: nil)
    |> Repo.update()
    |> tap(&broadcast_updated/1)
  end

  @doc """
  Puts the run's `:publishing` page back once Step 9 gave up: `:published`
  when it was published before (its URL kept), else `:ready`, with `reason`
  as its error. Called by the Step 9 worker with the job's run id.
  """
  def fail_publishing_pages(run_id, reason) when is_integer(run_id) and is_binary(reason) do
    run_id
    |> restore_publishing_pages(reason)
    |> Enum.each(&broadcast_page_updated/1)
  end

  @doc """
  The page as one self-contained HTML file to download, named after the
  Brief's slug (`strona.html` without a usable slug). Any page with a
  written Brief has one, whether or not it is published.

  Returns `{:ok, %{filename:, html:}}` or `{:error, :not_found | :not_ready}`.
  """
  def content_file(%Scope{} = scope, page_id) do
    with {:ok, page} <- fetch_page(scope, page_id),
         :ok <- ensure_content_file(page) do
      {:ok, %{filename: content_filename(page.brief), html: render(page)}}
    end
  end

  @doc """
  The Page HTML for a page with a Brief and its run preloaded
  (`get_page/2`), or nil while the Brief isn't written.
  """
  def render(%Page{brief: %Brief{} = brief, run: %Run{mode: mode}}), do: Template.render(brief, %{mode: mode})
  def render(%Page{brief: nil}), do: nil

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

  defp ensure_editable(%Page{status: status}) do
    if status in Page.editable_statuses(), do: :ok, else: {:error, :not_editable}
  end

  defp publish_in_locked_run(%Page{id: page_id, run_id: run_id}) do
    run = Research.lock_run!(run_id)

    with :ok <- ensure_run_idle(run),
         released_page_ids = restore_publishing_pages(run_id, nil),
         page = Repo.get!(Page, page_id),
         :ok <- ensure_publishable(page),
         {:ok, publishing_page} <- page |> Ecto.Changeset.change(status: :publishing, error: nil) |> Repo.update(),
         {:ok, started_run} <- Pipeline.start_step(run, @publish_step) do
      {:ok, %{page: publishing_page, run: started_run, released_page_ids: released_page_ids}}
    end
  end

  defp ensure_run_idle(run) do
    if Research.idle?(run), do: :ok, else: {:error, :run_busy}
  end

  defp restore_publishing_pages(run_id, error) do
    restore_publishing_pages_by_history(run_id, %{published_before?: true, error: error}) ++
      restore_publishing_pages_by_history(run_id, %{published_before?: false, error: error})
  end

  defp restore_publishing_pages_by_history(run_id, %{published_before?: published_before?, error: error}) do
    {_count, page_ids} =
      Page
      |> from(as: :page)
      |> where([page: page], page.run_id == ^run_id and page.status == ^:publishing)
      |> where([page: page], is_nil(page.published_url) != ^published_before?)
      |> select([page: page], page.id)
      |> Repo.update_all(
        set: [status: restored_status(published_before?), error: error, updated_at: DateTime.utc_now(:second)]
      )

    page_ids
  end

  defp restored_status(true), do: :published
  defp restored_status(false), do: :ready

  defp ensure_publishable(%Page{status: status, brief: %Brief{} = brief}) do
    if status in Page.publishable_statuses() and Brief.changeset(brief, %{}).valid?,
      do: :ok,
      else: {:error, :not_publishable}
  end

  defp ensure_publishable(%Page{brief: nil}), do: {:error, :not_publishable}

  defp ensure_content_file(%Page{status: status, brief: %Brief{}}) do
    if status in Page.content_file_statuses(), do: :ok, else: {:error, :not_ready}
  end

  defp ensure_content_file(%Page{brief: nil}), do: {:error, :not_ready}

  defp content_filename(%Brief{slug: slug}) do
    if is_binary(slug) and Regex.match?(@content_filename_format, slug),
      do: slug <> ".html",
      else: @fallback_content_filename <> ".html"
  end

  defp broadcast_updated({:ok, page}), do: broadcast_page_updated(page)
  defp broadcast_updated({:error, _changeset}), do: :ok

  defp topic(page_or_id), do: "page:#{page_id(page_or_id)}"

  defp page_id(%Page{id: page_id}), do: page_id
  defp page_id(page_id), do: page_id
end
