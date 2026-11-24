defmodule Dirmoon.Pages.Brief do
  @moduledoc """
  The Brief: the plan and content for one Produced Page. Stored embedded in a
  page's `brief` column and rendered by `Dirmoon.Pages.Template`.

  Only the H1 and at least one section question are required; every other
  blank field renders as a Placeholder.

  The sections form (screen 4) reorders, adds and drops sections with the
  `sections_sort` and `sections_drop` params (Ecto's `:sort_param` and
  `:drop_param`), and moves one section a place up with
  `sections_move_up` (a list of section indexes, applied to `sections_sort`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @fact_count 3
  @max_sections 12
  @max_nav_links 3

  @text_fields [
    :business_name,
    :title,
    :h1,
    :slug,
    :breadcrumb,
    :intro,
    :cta_label,
    :closing_prompt,
    :phone,
    :email,
    :address,
    :short_answer,
    :primary_phrase,
    :plausible_domain
  ]

  @slug_format ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @host_format ~r/\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/
  @email_format ~r/\A[^\s@<>"']+@[^\s@<>"']+\.[^\s@<>"']+\z/

  @primary_key false
  embedded_schema do
    field :business_name, :string
    field :title, :string
    field :h1, :string
    field :slug, :string
    field :breadcrumb, :string
    field :intro, :string
    field :cta_label, :string
    field :closing_prompt, :string
    field :nav_links, {:array, :string}, default: []
    field :phone, :string
    field :email, :string
    field :address, :string
    field :short_answer, :string
    field :phrases, {:array, :string}, default: []
    field :primary_phrase, :string
    field :plausible_domain, :string

    embeds_many :facts, Fact, on_replace: :delete, primary_key: false do
      field :label, :string
      field :value, :string
    end

    embeds_many :sections, Section, on_replace: :delete, primary_key: false do
      field :question, :string
      field :answer, :string
    end
  end

  def fact_count, do: @fact_count

  @doc """
  Validates a Brief from string- or atom-keyed params. The slug is lowercase
  ASCII words joined by hyphens; the Plausible domain is a bare host; the
  primary phrase is one of the Brief's phrases.
  """
  def changeset(brief, attrs) do
    moved_attrs = move_sections_up(attrs)

    brief
    |> cast(moved_attrs, @text_fields ++ [:nav_links, :phrases])
    |> update_change(:nav_links, &drop_blank/1)
    |> update_change(:phrases, &drop_blank/1)
    |> update_change(:plausible_domain, &downcase/1)
    |> update_change(:primary_phrase, &trim/1)
    |> cast_embed(:facts, with: &fact_changeset/2)
    |> cast_embed(:sections,
      with: &section_changeset/2,
      required: true,
      sort_param: :sections_sort,
      drop_param: :sections_drop
    )
    |> validate_required([:h1])
    |> validate_length(:facts, is: @fact_count)
    |> validate_length(:sections, min: 1, max: @max_sections)
    |> validate_length(:nav_links, max: @max_nav_links)
    |> validate_format(:slug, @slug_format)
    |> validate_format(:plausible_domain, @host_format)
    |> validate_format(:email, @email_format)
    |> validate_primary_phrase()
  end

  @doc """
  The Plausible domain when it is a bare host, otherwise nil, so a value that
  skipped the changeset is never rendered.
  """
  def plausible_domain(%__MODULE__{plausible_domain: domain}) when is_binary(domain) do
    if Regex.match?(@host_format, domain), do: domain
  end

  def plausible_domain(%__MODULE__{}), do: nil

  @doc """
  True for a value shaped like an e-mail address, so it can become a `mailto:`
  link.
  """
  def email?(email) when is_binary(email), do: Regex.match?(@email_format, email)
  def email?(_email), do: false

  defp move_sections_up(%{"sections_move_up" => moved, "sections_sort" => sort} = attrs)
       when is_list(moved) and is_list(sort) do
    moved_sort = Enum.reduce(moved, sort, &move_up/2)
    Map.put(attrs, "sections_sort", moved_sort)
  end

  defp move_sections_up(attrs), do: attrs

  defp move_up(index, sort) do
    case Enum.find_index(sort, &(&1 == index)) do
      position when is_integer(position) and position > 0 ->
        sort
        |> List.delete_at(position)
        |> List.insert_at(position - 1, index)

      _first_or_absent ->
        sort
    end
  end

  defp fact_changeset(fact, attrs), do: cast(fact, attrs, [:label, :value])

  defp section_changeset(section, attrs) do
    section
    |> cast(attrs, [:question, :answer])
    |> validate_required([:question])
  end

  defp drop_blank(nil), do: []

  defp drop_blank(values) do
    values
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp validate_primary_phrase(changeset) do
    phrases = get_field(changeset, :phrases)

    validate_change(changeset, :primary_phrase, fn :primary_phrase, primary_phrase ->
      if primary_phrase in phrases, do: [], else: [primary_phrase: "must be one of the phrases"]
    end)
  end
end
