defmodule Dirmoon.Pages.Brief do
  @moduledoc """
  The Brief: the plan and the text of one page about a Chosen Niche, which
  the owner hands to whoever builds their site. Stored embedded in a Page's
  `brief` column.

  Only the H1 and at least one section question are required. Keys a Brief
  stored before the page build was removed (breadcrumb, button label, closing
  prompt, menu links, Fact Tiles, Plausible domain) are ignored on load and
  dropped when the Brief is next saved.

  The sections form (screen 4) reorders, adds and drops sections with the
  `sections_sort` and `sections_drop` params (Ecto's `:sort_param` and
  `:drop_param`), and moves one section a place up with
  `sections_move_up` (a list of section indexes, applied to `sections_sort`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @max_sections 12

  @text_fields [
    :business_name,
    :title,
    :h1,
    :slug,
    :intro,
    :phone,
    :email,
    :address,
    :short_answer,
    :primary_phrase
  ]

  @slug_format ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @email_format ~r/\A[^\s@<>"']+@[^\s@<>"']+\.[^\s@<>"']+\z/

  @primary_key false
  embedded_schema do
    field :business_name, :string
    field :title, :string
    field :h1, :string
    field :slug, :string
    field :intro, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :short_answer, :string
    field :phrases, {:array, :string}, default: []
    field :primary_phrase, :string

    embeds_many :sections, Section, on_replace: :delete, primary_key: false do
      field :question, :string
      field :answer, :string
    end
  end

  @doc """
  Validates a Brief from string- or atom-keyed params. The slug is lowercase
  ASCII words joined by hyphens; the e-mail is shaped like an address; the
  primary phrase is one of the Brief's phrases.
  """
  def changeset(brief, attrs) do
    moved_attrs = move_sections_up(attrs)

    brief
    |> cast(moved_attrs, [:phrases | @text_fields])
    |> update_change(:phrases, &drop_blank/1)
    |> update_change(:primary_phrase, &trim/1)
    |> cast_embed(:sections,
      with: &section_changeset/2,
      required: true,
      sort_param: :sections_sort,
      drop_param: :sections_drop
    )
    |> validate_required([:h1])
    |> validate_length(:sections, min: 1, max: @max_sections)
    |> validate_format(:slug, @slug_format)
    |> validate_format(:email, @email_format)
    |> validate_primary_phrase()
  end

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

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp validate_primary_phrase(changeset) do
    phrases = get_field(changeset, :phrases)

    validate_change(changeset, :primary_phrase, fn :primary_phrase, primary_phrase ->
      if primary_phrase in phrases, do: [], else: [primary_phrase: "must be one of the phrases"]
    end)
  end
end
