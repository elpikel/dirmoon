defmodule DirmoonWeb.PageHTML do
  @moduledoc """
  The landing page rendered by `DirmoonWeb.PageController`, and its two
  sign-up forms, `:hero` and `:closing`, also re-rendered by
  `DirmoonWeb.SignUpController` when a submitted email is invalid.

  See the `page_html` directory for all templates available.
  """
  use DirmoonWeb, :html

  embed_templates "page_html/*"

  @sign_up_form_names [:hero, :closing]

  @doc """
  Returns an empty form for each landing sign-up form, keyed by its name.
  """
  def sign_up_forms do
    Map.new(@sign_up_form_names, &{&1, to_form(%{}, as: :user)})
  end

  @doc """
  Returns the landing sign-up forms with the submitted one built from its
  changeset, so only that form shows the submitted email and its errors.
  """
  def sign_up_forms(submitted_form_name, changeset_or_params) when submitted_form_name in @sign_up_form_names do
    Map.put(sign_up_forms(), submitted_form_name, to_form(changeset_or_params, as: :user))
  end

  @doc """
  Returns the sign-up form named by the hidden `form` field, the hero form
  when it names none.
  """
  def submitted_sign_up_form_name("closing"), do: :closing
  def submitted_sign_up_form_name(_form_field), do: :hero

  @doc """
  Returns the landing page path that scrolls to the given sign-up form's
  section.
  """
  def sign_up_form_path(:hero), do: ~p"/"
  def sign_up_form_path(:closing), do: ~p"/" <> "#closing"

  @doc """
  Returns the confirmation shown after a sign-up, identical for new emails and
  emails that already have a User.
  """
  def sign_up_confirmation_message(email), do: "Wysłaliśmy link logowania na #{email}. Sprawdź skrzynkę."

  attr :name, :atom, required: true, values: @sign_up_form_names
  attr :form, Phoenix.HTML.Form, required: true
  attr :confirmation, :string, default: nil, doc: "shown in place of the form after a sign-up"

  defp sign_up_form(%{confirmation: confirmation} = assigns) when is_binary(confirmation) do
    ~H"""
    <.prompt_box
      id={"sign-up-confirmation-#{@name}"}
      role="status"
      class="flex w-full max-w-[640px] items-center justify-center gap-3 px-6 py-5 text-[17px] font-medium text-ink"
    >
      <.icon name="hero-envelope" class="size-5 shrink-0" />
      <span>{@confirmation}</span>
    </.prompt_box>
    """
  end

  defp sign_up_form(assigns) do
    assigns = assign(assigns, :email_input_id, "sign-up-#{assigns.name}-email")

    ~H"""
    <.form
      for={@form}
      id={"sign-up-form-#{@name}"}
      action={~p"/sign-up"}
      method="post"
      class="flex w-full max-w-[640px] flex-col items-center gap-4 text-left"
    >
      <input type="hidden" name="form" value={@name} />
      <.prompt_box class={[
        "flex w-full flex-wrap items-start gap-3 p-3 pl-5 max-sm:pl-4",
        "has-[input:focus-visible]:outline-2 has-[input:focus-visible]:outline-offset-4 has-[input:focus-visible]:outline-ink"
      ]}>
        <label for={@email_input_id} class="sr-only">Adres e-mail</label>
        <div class="min-w-0 flex-[1_1_240px] *:mb-0">
          <.input
            field={@form[:email]}
            id={@email_input_id}
            type="email"
            placeholder="ty@firma.pl"
            autocomplete="email"
            spellcheck="false"
            required
            class="min-h-12 w-full border-0 bg-transparent p-0 text-[19px] font-medium tracking-[-0.01em] text-ink placeholder:text-body-muted focus-visible:outline-none"
          />
        </div>
        <.button variant="dark" size="large" type="submit" class="flex-none max-sm:w-full">
          Załóż konto
        </.button>
      </.prompt_box>
      <p class="text-[13px] text-body-muted">Wyślemy link logowania na ten adres. Bez hasła.</p>
    </.form>
    """
  end
end
