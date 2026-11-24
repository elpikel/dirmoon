defmodule DirmoonWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as flashes, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  Styling uses Tailwind utilities mapped to the dirmoon design tokens
  (`assets/css/app.css`, values in `assets/css/tokens.css`); no other colour
  is used. Buttons live in `DirmoonWeb.UI.button/1`. The tokens have no red,
  so error states use `--warn`. Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: DirmoonWeb.Gettext

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices. An info notice closes itself after five seconds; an
  error notice stays until it is closed.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook={@kind == :info && ".AutoDismissFlash"}
      role="alert"
      class="pointer-events-auto"
      {@rest}
    >
      <div
        data-kind={@kind}
        class={[
          "flex w-full items-start gap-3 rounded-tile border bg-white py-3 pr-1 pl-4 text-sm text-ink shadow-nav",
          @kind == :info && "border-line",
          @kind == :error && "border-warn"
        ]}
      >
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="mt-0.5 size-5 shrink-0 text-ink"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="mt-0.5 size-5 shrink-0 text-warn"
        />
        <div class="flex-1 text-wrap">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p class="text-body">{msg}</p>
        </div>
        <button
          type="button"
          class="group -my-2 inline-flex size-target-min shrink-0 cursor-pointer items-center justify-center rounded-control"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-5 text-body-muted group-hover:text-ink" />
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoDismissFlash">
      export default {
        mounted() {
          this.timer = setTimeout(() => this.js().exec(this.el.getAttribute("phx-click")), 5000)
        },
        destroyed() {
          clearTimeout(this.timer)
        }
      }
    </script>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Surface

  On the app's dark slate shell pass `surface="slate"`: the label, the field
  and its errors switch to the slate tokens and the field drops its bottom
  margin, so the form lays fields out with a gap.

  ```heex
  <.input field={@form[:title]} label="Tytuł strony" surface="slate" />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :surface, :string,
    default: "light",
    values: ~w(light slate),
    doc: "the background the field sits on: light pages and cards, or the app's dark slate shell"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={field_class(@surface)}>
      <label
        for={@id}
        class={[
          "inline-flex min-h-target-min cursor-pointer items-center gap-3 text-sm",
          text_class(@surface)
        ]}
      >
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              "size-5 shrink-0 cursor-pointer rounded-[4px] border border-line-strong accent-ink"
          }
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors} surface={@surface}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={field_class(@surface)}>
      <label for={@id} class="flex flex-col gap-1.5">
        <span :if={@label} class={label_class(@surface)}>{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || [control_class(@surface), "cursor-pointer"],
            @errors != [] && (@error_class || "border-warn")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors} surface={@surface}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={field_class(@surface)}>
      <label for={@id} class="flex flex-col gap-1.5">
        <span :if={@label} class={label_class(@surface)}>{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              [control_class(@surface), textarea_height_class(@surface), "py-3 leading-normal"],
            @errors != [] && (@error_class || "border-warn")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors} surface={@surface}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={field_class(@surface)}>
      <label for={@id} class="flex flex-col gap-1.5">
        <span :if={@label} class={label_class(@surface)}>{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || control_class(@surface),
            @errors != [] && (@error_class || "border-warn")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors} surface={@surface}>{msg}</.error>
    </div>
    """
  end

  ## JS Commands

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(DirmoonWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DirmoonWeb.Gettext, "errors", msg, opts)
    end
  end

  attr :surface, :string, required: true
  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p class={["flex items-center gap-2 text-sm", text_class(@surface)]}>
      <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-warn" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp field_class("light"), do: "mb-4 flex flex-col gap-1.5"
  defp field_class("slate"), do: "flex flex-col gap-1.5"

  defp label_class("light"), do: "text-sm font-medium text-ink"
  defp label_class("slate"), do: "text-[13px] font-medium text-on-slate-2"

  defp text_class("light"), do: "text-ink"
  defp text_class("slate"), do: "text-on-slate"

  defp control_class("light"),
    do:
      "min-h-target-min w-full rounded-control border border-line bg-white px-3.5 text-[15px] text-ink transition-colors duration-150 placeholder:text-body-muted hover:border-line-strong focus:border-ink"

  defp control_class("slate"),
    do:
      "min-h-target-min w-full rounded-control border border-slate-line bg-slate-raised px-3.5 text-sm text-on-slate transition-colors duration-150 placeholder:text-on-slate-muted hover:border-slate-line-strong focus:border-on-slate-2 focus:outline-none"

  defp textarea_height_class("light"), do: "min-h-[120px]"
  defp textarea_height_class("slate"), do: "min-h-[96px]"
end
