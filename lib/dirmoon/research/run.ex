defmodule Dirmoon.Research.Run do
  @moduledoc """
  A Research Run: one pass of the pipeline for one business description, in
  one Mode, for one Market (a country and a language) and optionally one
  city. Belongs to one Account. The country and language names are stored
  with the run when it starts, so showing them never needs the Market lists.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Markets.Country
  alias Dirmoon.Markets.Language
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps

  @modes [:new_idea, :existing_site]
  @statuses [:running, :stopped, :failed, :awaiting_choice]
  @max_priority_services 5
  @scoring_step Steps.number!(:scoring)

  schema "research_runs" do
    field :description, :string
    field :mode, Ecto.Enum, values: @modes
    field :country_code, :string
    field :country_name, :string
    field :language_code, :string
    field :language_name, :string
    field :location_code, :integer
    field :city, :string
    field :city_location_code, :integer
    field :domain, :string
    field :priority_services, {:array, :string}, default: []
    field :status, Ecto.Enum, values: @statuses

    belongs_to :account, Account
    has_many :steps, RunStep

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes

  def statuses, do: @statuses

  def max_priority_services, do: @max_priority_services

  @doc """
  Whether the run's results are ready: Step 7 (Scoring) is done, so its
  Niches are scored and one can be chosen. Read from the run's Steps, which
  must be loaded; it holds whatever the run's status, so a run writing a
  Brief (`:running`), or one that failed or stopped in Step 8, still has
  its results, while a run resumed from an earlier Step has none until Step 7
  finishes again.
  """
  def results_ready?(%__MODULE__{steps: steps}) when is_list(steps) do
    Enum.any?(steps, &(&1.number == @scoring_step and &1.status == :done))
  end

  @doc """
  Whether a Niche of the run can be chosen now: its results are ready
  (`results_ready?/1`) and the run isn't stopped (a stopped run is resumed
  first). Needs the run's Steps. `Dirmoon.Niches.choose/2` also requires the
  run to be idle, checked with the run locked.
  """
  def choosable?(%__MODULE__{status: :stopped}), do: false
  def choosable?(%__MODULE__{} = run), do: results_ready?(run)

  @doc """
  Validates a run's input as typed in the form: the chosen country and
  language codes are cast, and `put_market/2` checks them against the Market
  lists; the domain is normalised to a bare host (`https://www.KKadwokat.pl/`
  → `kkadwokat.pl`); blank Priority Services are dropped.
  """
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:description, :mode, :country_code, :language_code, :city, :domain, :priority_services])
    |> update_change(:description, &String.trim/1)
    |> update_change(:city, &String.trim/1)
    |> update_change(:priority_services, &drop_blank_services/1)
    |> update_change(:domain, &normalise_domain/1)
    |> validate_required([:description, :mode, :country_code, :language_code])
    |> validate_required_domain()
    |> validate_format(:domain, ~r/^[^\s.\/]+(\.[^\s.\/]+)+$/u)
    |> validate_length(:priority_services, max: @max_priority_services)
    |> check_constraint(:priority_services, name: :research_runs_priority_services_at_most_five)
    |> check_constraint(:domain, name: :research_runs_domain_required_for_existing_site)
  end

  @doc """
  Puts the chosen Market on a run's changeset: the stored country (its
  keyword location code and name) and language (its name) that match the
  cast codes, as `Dirmoon.Markets.find_market/1` found them. A code that is
  given but matches nothing stored is an error on that field; the posted
  location code is never read.
  """
  def put_market(changeset, %{country: country, language: language}) do
    changeset
    |> put_country(country)
    |> put_language(language)
  end

  defp put_country(changeset, %Country{location_code: location_code, name: name}) do
    change(changeset, location_code: location_code, country_name: name)
  end

  defp put_country(changeset, nil), do: unavailable_unless_blank(changeset, :country_code)

  defp put_language(changeset, %Language{name: name}), do: put_change(changeset, :language_name, name)
  defp put_language(changeset, nil), do: unavailable_unless_blank(changeset, :language_code)

  defp unavailable_unless_blank(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _code -> add_error(changeset, field, "is not available")
    end
  end

  defp drop_blank_services(services) do
    services
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalise_domain(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^[a-z][a-z0-9+.-]*:\/\//, "")
    |> String.split(["/", "?", "#"], parts: 2)
    |> hd()
    |> String.replace_prefix("www.", "")
    |> blank_to_nil()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp validate_required_domain(changeset) do
    case get_field(changeset, :mode) do
      :existing_site -> validate_required(changeset, [:domain])
      _new_idea_or_missing -> changeset
    end
  end
end
