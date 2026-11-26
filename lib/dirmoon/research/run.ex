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
  alias Dirmoon.WebPage.HostName

  @modes [:new_idea, :existing_site]
  @statuses [:running, :stopped, :failed, :awaiting_choice]
  @max_priority_services 5
  @host_name_format ~r/^[^\x00-\x20\x7F-\x{10FFFF}.\/:@\\]+(\.[^\x00-\x20\x7F-\x{10FFFF}.\/:@\\]+)+$/u
  @max_host_name_bytes 253
  @scheme_prefix ~r/^[a-z][a-z0-9+.-]*:\/\//i
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
  lists; the domain is normalised to a bare host in ASCII form
  (`https://www.KKadwokat.pl/` → `kkadwokat.pl`, `żółw.pl` →
  `xn--w-uga1v8h.pl`); blank Priority Services are dropped.
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
    |> validate_change(:domain, &host_name_errors/2)
    |> validate_length(:priority_services, max: @max_priority_services)
    |> check_constraint(:priority_services, name: :research_runs_priority_services_at_most_five)
    |> check_constraint(:domain, name: :research_runs_domain_required_for_existing_site)
  end

  @doc """
  The bare host a typed site address names, by the rule the changeset uses:
  the address is parsed as a URL (with or without a scheme) and only its
  host is kept, so the scheme, user name and password, port, path, query
  and fragment go, as do a trailing dot and a leading `www.`; the host is
  lower-cased (`https://user:pw@www.KKadwokat.pl:8080/oferta` →
  `kkadwokat.pl`). An international name is kept in its ASCII form
  (`Dirmoon.WebPage.HostName`: `Żółw.pl` → `xn--w-uga1v8h.pl`), the form
  the site is requested, looked up and compared in; full-width letters,
  digits and dots become their ASCII spelling on the way.

  Returns `{:ok, domain}`, or `:error` for a blank address or one that
  names no host name: dot-separated ASCII labels without `:`, `@`, `\\`,
  `/`, whitespace or control characters, at most 253 bytes, so an
  international name that can't be encoded names none. An address with a
  backslash anywhere names no host, since URL parsers disagree on where its
  host ends.
  """
  def normalised_domain(address) when is_binary(address) do
    case normalise_domain(address) do
      nil -> :error
      domain -> if host_name?(domain), do: {:ok, domain}, else: :error
    end
  end

  def normalised_domain(_not_text), do: :error

  @doc """
  The run's domain in the form it is requested, looked up and compared in:
  the bare host in ASCII form (`Dirmoon.WebPage.HostName.bare/1`). Runs
  stored before domains were kept in ASCII form may hold the Unicode form
  (`żółw.pl`); this gives `xn--w-uga1v8h.pl` for those too. `nil` for a run
  without a domain.
  """
  @spec ascii_domain(%__MODULE__{}) :: String.t() | nil
  def ascii_domain(%__MODULE__{domain: domain}) when is_binary(domain), do: HostName.bare(domain)
  def ascii_domain(%__MODULE__{domain: nil}), do: nil

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

  defp normalise_domain(address) do
    typed = String.trim(address)

    if typed |> String.replace(@scheme_prefix, "") |> String.trim() == "" do
      nil
    else
      typed
      |> host_of()
      |> ascii_or_as_typed()
      |> String.downcase()
      |> String.trim_trailing(".")
      |> String.replace_prefix("www.", "")
    end
  end

  defp host_of(typed) do
    with false <- String.contains?(typed, "\\"),
         %URI{host: host} when is_binary(host) and host != "" <- typed |> with_scheme() |> URI.parse() do
      host
    else
      _no_host -> typed
    end
  end

  defp ascii_or_as_typed(host) do
    case HostName.to_ascii(host) do
      {:ok, ascii} -> ascii
      :error -> host
    end
  end

  defp with_scheme(typed) do
    if Regex.match?(@scheme_prefix, typed), do: typed, else: "//" <> typed
  end

  defp host_name?(domain), do: byte_size(domain) <= @max_host_name_bytes and Regex.match?(@host_name_format, domain)

  defp host_name_errors(:domain, domain) do
    if host_name?(domain), do: [], else: [domain: "has invalid format"]
  end

  defp validate_required_domain(changeset) do
    case get_field(changeset, :mode) do
      :existing_site -> validate_required(changeset, [:domain])
      _new_idea_or_missing -> changeset
    end
  end
end
