defmodule Dirmoon.Pages.Template do
  @moduledoc """
  Renders a Brief into the fixed Page template (design handover
  section 8.4) as one self-contained HTML document: the stylesheet is inlined
  and the only external resource is the Plausible script when the Brief has a
  domain. Brief content is always escaped; a missing value is shown as a
  visible Placeholder.
  """
  use Phoenix.Component

  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Placeholders

  @css_path Path.join(__DIR__, "template.css")
  @external_resource @css_path
  @css File.read!(@css_path)

  @modes [:new_idea, :existing_site]
  @default_cta_label "Skontaktuj się"
  @default_closing_prompt "Masz pytania? Napisz lub zadzwoń."
  @default_breadcrumb "Strona główna"
  @pill_words 4
  @phone_format ~r/\A\+?[\d\s()\-]+\z/
  @min_phone_digits 9

  @doc """
  The inlined stylesheet; every colour in it is a design token value.
  """
  def css, do: @css

  @doc """
  The full HTML document for `brief`. Both Modes get the same working page.
  """
  def render(%Brief{} = brief, %{mode: mode}) when mode in @modes do
    %{page: page_assigns(brief)}
    |> document()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp page_assigns(brief) do
    sections = Enum.with_index(brief.sections, fn section, position -> %{section: section, index: position + 1} end)

    %{
      title: first_present([brief.title, brief.h1]),
      description: present(brief.intro),
      plausible_domain: Brief.plausible_domain(brief),
      css: @css,
      business_name: brief.business_name,
      h1: brief.h1,
      breadcrumb: first_present([brief.breadcrumb, @default_breadcrumb]),
      intro: brief.intro,
      cta_label: first_present([brief.cta_label, @default_cta_label]),
      closing_prompt: first_present([brief.closing_prompt, @default_closing_prompt]),
      nav_links: nav_links(brief.nav_links, length(sections)),
      phone: brief.phone,
      phone_href: phone_href(brief.phone),
      email: brief.email,
      email_href: email_href(brief.email),
      address: brief.address,
      fact_tiles: padded_fact_tiles(brief.fact_tiles),
      sections: sections,
      short_answer: brief.short_answer
    }
  end

  defp document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@page.title}</title>
        <meta :if={@page.description} name="description" content={@page.description} />
        <style>
          <%= Phoenix.HTML.raw(@page.css) %>
        </style>
        <script
          :if={@page.plausible_domain}
          defer
          data-domain={@page.plausible_domain}
          src="https://plausible.io/js/script.js"
        >
        </script>
      </head>
      <body>
        <.site_header page={@page} />
        <main>
          <.hero page={@page} />
          <.jump_strip sections={@page.sections} />
          <.page_section
            :for={numbered <- @page.sections}
            section={numbered.section}
            index={numbered.index}
            short_answer={@page.short_answer}
          />
        </main>
        <.closing page={@page} />
      </body>
    </html>
    """
  end

  defp site_header(assigns) do
    ~H"""
    <header class="site-header" data-block="header">
      <div class="container">
        <span class="business-name"><.content text={@page.business_name} missing={:business_name} /></span>
        <nav class="site-nav" aria-label="Główna">
          <a :for={link <- @page.nav_links} class="nav-link" href={link.href}>
            <.content text={link.label} missing={:nav_link} />
          </a>
          <a class="button button-dark" href="#kontakt"><.content
            text={@page.cta_label}
            missing={:cta_label}
          /></a>
        </nav>
      </div>
    </header>
    """
  end

  defp hero(assigns) do
    ~H"""
    <section class="hero" data-block="hero">
      <div class="container hero-inner">
        <p class="breadcrumb"><.content text={@page.breadcrumb} missing={:breadcrumb} /></p>
        <h1 class="hero-title"><.content text={@page.h1} missing={:h1} /></h1>
        <p class="intro"><.content text={@page.intro} missing={:intro} /></p>
        <div class="hero-actions">
          <a class="button button-dark" href="#kontakt">
            <.content text={@page.cta_label} missing={:cta_label} /><.arrow_icon />
          </a>
          <a :if={@page.phone_href} class="phone" href={@page.phone_href}><.phone_icon />{@page.phone}</a>
          <span :if={!@page.phone_href} class="phone">
            <.phone_icon /><.content text={@page.phone} missing={:phone} />
          </span>
        </div>
        <div class="fact-tiles">
          <div :for={fact_tile <- @page.fact_tiles} class="fact-tile">
            <span class="fact-tile-label"><.content text={fact_tile.label} missing={:fact_tile_label} /></span>
            <span class="fact-tile-value">
              <.content text={fact_tile.value} missing={Placeholders.for_fact_tile(fact_tile.label)} />
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp jump_strip(assigns) do
    ~H"""
    <nav class="jump-strip" data-block="jump-strip" aria-label="Na tej stronie">
      <div class="container">
        <span class="jump-label">Na tej stronie</span>
        <a :for={numbered <- @sections} class="pill" href={"#" <> section_anchor(numbered.index)}>
          <.content text={pill_label(numbered.section.question)} missing={:question} />
        </a>
      </div>
    </nav>
    """
  end

  defp page_section(assigns) do
    ~H"""
    <section class="page-section" data-block="section" aria-labelledby={section_anchor(@index)}>
      <div class="container">
        <span class={if(@index == 1, do: "badge badge-first", else: "badge")} aria-hidden="true">{badge(
          @index
        )}</span>
        <div class="section-body">
          <h2 id={section_anchor(@index)}>
            <.content text={@section.question} missing={:question} />
          </h2>
          <div class="answer">
            <p :for={paragraph <- paragraphs(@section.answer)}>
              <.content text={paragraph} missing={:answer} />
            </p>
          </div>
          <div :if={@index == 1} class="short-answer">
            <span class="short-answer-label">W skrócie</span>
            <p class="short-answer-text"><.content text={@short_answer} missing={:short_answer} /></p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp closing(assigns) do
    ~H"""
    <footer id="kontakt" class="closing" data-block="closing">
      <div class="container">
        <div class="closing-text">
          <p class="closing-prompt">
            <.content text={@page.closing_prompt} missing={:closing_prompt} />
          </p>
          <div class="contact">
            <a :if={@page.phone_href} href={@page.phone_href}>{@page.phone}</a>
            <span :if={!@page.phone_href}><.content text={@page.phone} missing={:phone} /></span>
            <a :if={@page.email_href} href={@page.email_href}>{@page.email}</a>
            <span :if={!@page.email_href}><.content text={@page.email} missing={:email} /></span>
            <span class="address"><.content text={@page.address} missing={:address} /></span>
          </div>
        </div>
        <a class="button button-lime" href={@page.phone_href || @page.email_href || "#kontakt"}>
          <.content text={@page.cta_label} missing={:cta_label} />
        </a>
      </div>
    </footer>
    """
  end

  attr :text, :any, required: true
  attr :missing, :any, required: true

  defp content(assigns) do
    assigns = assign(assigns, :text_parts, text_parts(assigns.text, assigns.missing))

    ~H"""
    <.text_part :for={text_part <- @text_parts} text_part={text_part} />
    """
  end

  attr :text_part, :map, required: true

  defp text_part(%{text_part: %{placeholder: true}} = assigns), do: ~H|<span class="placeholder">{@text_part.text}</span>|

  defp text_part(assigns), do: ~H"{@text_part.text}"

  defp arrow_icon(assigns) do
    ~H"""
    <svg
      aria-hidden="true"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    ><path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path></svg>
    """
  end

  defp phone_icon(assigns) do
    ~H"""
    <svg
      aria-hidden="true"
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    ><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z">
    </path></svg>
    """
  end

  defp text_parts(text, missing) do
    case present(text) do
      nil -> [%{text: missing_placeholder(missing), placeholder: true}]
      present_text -> Placeholders.split(present_text)
    end
  end

  defp missing_placeholder(missing) when is_atom(missing), do: Placeholders.for_field(missing)
  defp missing_placeholder(missing) when is_binary(missing), do: missing

  defp nav_links(labels, section_count) do
    Enum.with_index(labels, fn label, position -> %{label: label, href: nav_href(position + 1, section_count)} end)
  end

  defp nav_href(index, section_count) when index <= section_count, do: "#" <> section_anchor(index)
  defp nav_href(_index, _section_count), do: "#kontakt"

  defp padded_fact_tiles(fact_tiles) do
    missing = max(Brief.fact_tile_count() - length(fact_tiles), 0)

    Enum.take(fact_tiles ++ List.duplicate(%Brief.FactTile{}, missing), Brief.fact_tile_count())
  end

  defp phone_href(phone) when is_binary(phone) do
    if Regex.match?(@phone_format, phone) and digit_count(phone) >= @min_phone_digits do
      "tel:" <> String.replace(phone, ~r/[^\d+]/, "")
    end
  end

  defp phone_href(_phone), do: nil

  defp digit_count(text), do: ~r/\d/ |> Regex.scan(text) |> length()

  defp email_href(email) do
    if Brief.email?(email), do: "mailto:" <> email
  end

  defp paragraphs(answer) do
    case present(answer) do
      nil ->
        [nil]

      text ->
        text
        |> String.split(~r/\R/u)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp pill_label(nil), do: nil

  defp pill_label(question) do
    question
    |> Placeholders.words()
    |> Enum.take(@pill_words)
    |> Enum.join(" ")
    |> String.replace(~r/[?!.,:;…]+\z/u, "")
  end

  defp section_anchor(index), do: "sekcja-#{index}"

  defp badge(index), do: index |> Integer.to_string() |> String.pad_leading(2, "0")

  defp first_present(values), do: Enum.find_value(values, &present/1)

  defp present(value) when is_binary(value) do
    if String.trim(value) != "", do: value
  end

  defp present(_value), do: nil
end
