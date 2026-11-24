defmodule DirmoonWeb.PageHTML do
  @moduledoc """
  Pages rendered by `DirmoonWeb.PageController`.

  See the `page_html` directory for all templates available.
  """
  use DirmoonWeb, :html

  embed_templates "page_html/*"
end
