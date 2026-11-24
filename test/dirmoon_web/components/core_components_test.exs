defmodule DirmoonWeb.CoreComponentsTest do
  use DirmoonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DirmoonWeb.CoreComponents

  test "an input on the light page has an ink label, a white field and ink errors under a bottom margin" do
    assigns = %{}

    document =
      parse(~H|<CoreComponents.input id="email" name="email" value="" label="E-mail" errors={["za krótki"]} />|)

    assert has_class?(document, "div", "mb-4")
    assert has_class?(document, "label span", "text-ink")

    for class <- ~w(bg-white border-line text-ink border-warn) do
      assert has_class?(document, "input#email", class)
    end

    assert has_class?(document, "p", "text-ink")
    assert document |> LazyHTML.query("p .hero-exclamation-circle.text-warn") |> Enum.count() == 1
    assert document |> LazyHTML.query("p") |> LazyHTML.text() |> String.trim() == "za krótki"
  end

  test "an input in the app has a light label, a dark gray field and errors readable on the app gray" do
    assigns = %{}

    document =
      parse(~H"""
      <CoreComponents.input
        id="title"
        name="title"
        value="Wynajem kamperów"
        label="Tytuł strony"
        errors={["nie może być pusty"]}
        surface="app"
      />
      """)

    refute has_class?(document, "div", "mb-4")
    assert document |> LazyHTML.query("label[for=title] span") |> LazyHTML.text() == "Tytuł strony"

    for class <- ~w(text-[13px] text-on-app-2) do
      assert has_class?(document, "label span", class)
    end

    for class <- ~w(bg-app-field border-app-line text-on-app placeholder:text-on-app-muted border-warn) do
      assert has_class?(document, "input#title", class)
    end

    refute has_class?(document, "input#title", "bg-white")
    assert has_class?(document, "p", "text-on-app")
    refute has_class?(document, "p", "text-ink")
    assert document |> LazyHTML.query("p .hero-exclamation-circle.text-warn") |> Enum.count() == 1
    assert document |> LazyHTML.query("p") |> LazyHTML.text() |> String.trim() == "nie może być pusty"
  end

  test "a textarea in the app takes the app label, field and error classes" do
    assigns = %{}

    document =
      parse(~H"""
      <CoreComponents.input
        id="intro"
        name="intro"
        type="textarea"
        value=""
        label="Wstęp"
        errors={["za długi"]}
        surface="app"
      />
      """)

    assert has_class?(document, "label span", "text-on-app-2")

    for class <- ~w(bg-app-field border-app-line text-on-app min-h-[96px] py-3) do
      assert has_class?(document, "textarea#intro", class)
    end

    assert has_class?(document, "p", "text-on-app")
  end

  test "a textarea on the light page keeps the white field and the taller minimum height" do
    assigns = %{}

    document = parse(~H|<CoreComponents.input id="notes" name="notes" type="textarea" value="" />|)

    for class <- ~w(bg-white border-line min-h-[120px]) do
      assert has_class?(document, "textarea#notes", class)
    end
  end

  test "a select in the app takes the app label, field and error classes" do
    assigns = %{}

    document =
      parse(~H"""
      <CoreComponents.input
        id="country"
        name="country"
        type="select"
        options={[{"Polska", "PL"}]}
        value="PL"
        label="Kraj"
        errors={["wybierz kraj"]}
        surface="app"
      />
      """)

    assert has_class?(document, "label span", "text-on-app-2")

    for class <- ~w(bg-app-field border-app-line text-on-app cursor-pointer border-warn) do
      assert has_class?(document, "select#country", class)
    end

    assert has_class?(document, "p", "text-on-app")
  end

  test "a checkbox in the app has a label and errors readable on the app gray" do
    assigns = %{}

    document =
      parse(~H"""
      <CoreComponents.input
        id="remember"
        name="remember"
        type="checkbox"
        label="Zapamiętaj"
        errors={["zaznacz"]}
        surface="app"
      />
      """)

    assert has_class?(document, "label[for=remember]", "text-on-app")
    refute has_class?(document, "label[for=remember]", "text-ink")
    assert has_class?(document, "p", "text-on-app")
    refute has_class?(document, "div", "mb-4")
  end

  test "a class given to an input in the app replaces the default field classes" do
    assigns = %{}

    document =
      parse(~H|<CoreComponents.input id="slug" name="slug" value="" class="font-mono" surface="app" />|)

    assert has_class?(document, "input#slug", "font-mono")
    refute has_class?(document, "input#slug", "bg-app-field")
    assert has_class?(document, "div", "flex")
  end

  defp parse(rendered) do
    rendered |> rendered_to_string() |> LazyHTML.from_fragment()
  end

  defp has_class?(document, selector, class) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("class")
    |> Enum.any?(fn classes -> class in String.split(classes || "") end)
  end
end
