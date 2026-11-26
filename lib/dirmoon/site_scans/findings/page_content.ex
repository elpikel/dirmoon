defmodule Dirmoon.SiteScans.Findings.PageContent do
  @moduledoc """
  Findings for the question "what does each page say?" (`:page_content`),
  over the readable pages Google may list
  (`Dirmoon.SiteScans.Findings.SitePages.with_content/1`). Each check is
  good when no page fails it; with no such page there is no Finding.

    * `:missing_title`: pages without a title (problem)
    * `:duplicate_titles`: one title on several pages (warning; figures
      `titles`, each `%{title:, pages:}`)
    * `:long_titles`: titles over 60 characters (warning; figures
      `lengths`, each `%{url:, length:}`)
    * `:short_titles`: titles under 10 characters (warning; figures
      `lengths`)
    * `:missing_description`: pages without a description (warning)
    * `:duplicate_descriptions`: one description on several pages (warning;
      figures `descriptions`, each `%{description:, pages:}`)
    * `:long_descriptions`: descriptions over 160 characters (warning;
      figures `lengths`)
    * `:missing_main_heading`: pages without a main heading (warning)
    * `:several_main_headings`: pages with more than one (warning; figures
      `counts`, each `%{url:, count:}`)
    * `:little_text`: pages with very little text
      (`SitePages.little_text?/1`; warning; figures `word_counts`, each
      `%{url:, word_count:}`). Pages in a language written without spaces
      are left out; when only those remain there is no Finding
    * `:duplicate_text`: pages with the same visible text (warning; figures
      `shared_texts`, each `%{pages:}`)
    * `:images_without_description`: pages with images lacking a
      description (warning; figures `images` and `without_description`,
      the totals over those pages)

  Lists in figures hold at most `Dirmoon.SiteScans.Finding.max_pages/0`
  items.
  """

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings.SitePages

  @question :page_content
  @checks [
    missing_title: [:problem, :good],
    duplicate_titles: [:warning, :good],
    long_titles: [:warning, :good],
    short_titles: [:warning, :good],
    missing_description: [:warning, :good],
    duplicate_descriptions: [:warning, :good],
    long_descriptions: [:warning, :good],
    missing_main_heading: [:warning, :good],
    several_main_headings: [:warning, :good],
    little_text: [:warning, :good],
    duplicate_text: [:warning, :good],
    images_without_description: [:warning, :good]
  ]
  @check_levels for {check, levels} <- @checks, level <- levels, do: {check, level}
  @max_title_length 60
  @min_title_length 10
  @max_description_length 160

  @doc "Every check this rule makes, with each level it can give: `[%{question:, check:, level:}]`."
  def checks, do: for({check, level} <- @check_levels, do: %{question: @question, check: check, level: level})

  @doc "The `:page_content` Findings of the site (`Dirmoon.SiteScans.Findings`)."
  def check(%{pages: pages}) do
    case SitePages.with_content(pages) do
      [] ->
        []

      content ->
        List.flatten([
          missing_text(content, %{check: :missing_title, key: "title", level: :problem}),
          shared_text(content, %{check: :duplicate_titles, key: "title", figure: :titles, label: :title}),
          text_length(content, %{check: :long_titles, key: "title", outside?: &(&1 > @max_title_length)}),
          text_length(content, %{check: :short_titles, key: "title", outside?: &(&1 < @min_title_length)}),
          missing_text(content, %{check: :missing_description, key: "description", level: :warning}),
          shared_text(content, %{
            check: :duplicate_descriptions,
            key: "description",
            figure: :descriptions,
            label: :description
          }),
          text_length(content, %{check: :long_descriptions, key: "description", outside?: &(&1 > @max_description_length)}),
          missing_main_heading(content),
          several_main_headings(content),
          little_text(content),
          duplicate_text(content),
          images_without_description(content)
        ])
    end
  end

  defp missing_text(content, %{check: check, key: key, level: level}) do
    case Enum.reject(content, &present?(&1.facts[key])) do
      [] -> finding(check, :good)
      missing -> finding(check, level, %{pages: urls(missing)})
    end
  end

  defp shared_text(content, %{check: check, key: key, figure: figure, label: label}) do
    shared =
      content
      |> Enum.filter(&present?(&1.facts[key]))
      |> Enum.group_by(&String.trim(&1.facts[key]))
      |> Enum.filter(fn {_text, pages} -> match?([_, _ | _], pages) end)
      |> Enum.sort_by(fn {text, pages} -> {-length(pages), text} end)

    case shared do
      [] ->
        finding(check, :good)

      shared ->
        shared_texts = Enum.map(shared, fn {text, pages} -> %{label => text, pages: urls(pages)} end)

        finding(check, :warning, %{
          pages: Enum.flat_map(shared_texts, & &1.pages),
          figures: %{figure => Enum.take(shared_texts, Finding.max_pages())}
        })
    end
  end

  defp text_length(content, %{check: check, key: key, outside?: outside?}) do
    lengths =
      content
      |> Enum.filter(&present?(&1.facts[key]))
      |> Enum.map(&%{url: &1.url, length: &1.facts[key] |> String.trim() |> String.length()})
      |> Enum.filter(&outside?.(&1.length))

    listed(check, lengths, :lengths)
  end

  defp missing_main_heading(content) do
    case Enum.filter(content, &(main_heading_count(&1) == 0)) do
      [] -> finding(:missing_main_heading, :good)
      missing -> finding(:missing_main_heading, :warning, %{pages: urls(missing)})
    end
  end

  defp several_main_headings(content) do
    content
    |> Enum.map(&%{url: &1.url, count: main_heading_count(&1)})
    |> Enum.filter(&(&1.count > 1))
    |> then(&listed(:several_main_headings, &1, :counts))
  end

  defp main_heading_count(page), do: page.facts["main_headings"] |> List.wrap() |> length()

  defp little_text(content) do
    case Enum.filter(content, &SitePages.words_countable?/1) do
      [] ->
        []

      countable ->
        countable
        |> Enum.filter(&SitePages.little_text?/1)
        |> Enum.map(&%{url: &1.url, word_count: &1.facts["word_count"]})
        |> then(&listed(:little_text, &1, :word_counts))
    end
  end

  defp duplicate_text(content) do
    shared_texts =
      content
      |> Enum.filter(&is_binary(&1.facts["text_fingerprint"]))
      |> Enum.group_by(& &1.facts["text_fingerprint"])
      |> Map.values()
      |> Enum.filter(&match?([_, _ | _], &1))
      |> Enum.map(&%{pages: urls(&1)})
      |> Enum.sort_by(&hd(&1.pages))

    case shared_texts do
      [] ->
        finding(:duplicate_text, :good)

      shared_texts ->
        finding(:duplicate_text, :warning, %{
          pages: Enum.flat_map(shared_texts, & &1.pages),
          figures: %{shared_texts: Enum.take(shared_texts, Finding.max_pages())}
        })
    end
  end

  defp images_without_description(content) do
    case Enum.filter(content, &(count(&1, "images_without_description") > 0)) do
      [] ->
        finding(:images_without_description, :good)

      lacking ->
        finding(:images_without_description, :warning, %{
          pages: urls(lacking),
          figures: %{
            images: lacking |> Enum.map(&count(&1, "images")) |> Enum.sum(),
            without_description: lacking |> Enum.map(&count(&1, "images_without_description")) |> Enum.sum()
          }
        })
    end
  end

  defp count(page, key) do
    case page.facts[key] do
      count when is_integer(count) -> count
      _missing -> 0
    end
  end

  defp listed(check, [], _figure), do: finding(check, :good)

  defp listed(check, items, figure),
    do:
      finding(check, :warning, %{
        pages: Enum.map(items, & &1.url),
        figures: %{figure => Enum.take(items, Finding.max_pages())}
      })

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  defp urls(pages), do: Enum.map(pages, & &1.url)

  defp finding(check, level, attributes \\ %{}) when {check, level} in @check_levels,
    do: Finding.new(Map.merge(attributes, %{question: @question, check: check, level: level}))
end
