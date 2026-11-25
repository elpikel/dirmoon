# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dirmoon, Dirmoon.DataForSEO.HTTP, base_url: "https://api.dataforseo.com", req_options: []

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
# `prices` are USD per million tokens, from OpenAI's pricing page (November 2026).
# A model missing here is refused, so a run never records an LLM call at no cost.
config :dirmoon, Dirmoon.LLM.OpenAI,
  base_url: "https://api.openai.com",
  model: "gpt-6.2-sol",
  req_options: [],
  prices: %{
    "gpt-6.2-astra" => %{input: "8.00", cached_input: "0.40", output: "40.00"},
    "gpt-6.2-sol" => %{input: "2.00", cached_input: "0.10", output: "10.00"},
    "gpt-6.1-terra" => %{input: "1.00", cached_input: "0.05", output: "5.00"},
    "gpt-6-luna" => %{input: "0.10", cached_input: "0.01", output: "0.50"}
  }

config :dirmoon, Dirmoon.Mailer, adapter: Swoosh.Adapters.Local
config :dirmoon, Dirmoon.Repo, types: Dirmoon.Repo.PostgrexTypes
config :dirmoon, Dirmoon.SearchConsole.Client.Google, req_options: []
config :dirmoon, Dirmoon.WebPage.HTTP, req_options: []

# Configure the endpoint
config :dirmoon, DirmoonWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DirmoonWeb.ErrorHTML, json: DirmoonWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dirmoon.PubSub,
  live_view: [signing_salt: "kElU6Rxm"]

config :dirmoon, Oban,
  engine: Oban.Engines.Basic,
  repo: Dirmoon.Repo,
  queues: [pipeline: 5],
  plugins: [Oban.Plugins.Pruner]

config :dirmoon, :scopes,
  user: [
    default: true,
    module: Dirmoon.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:account, :id],
    schema_key: :account_id,
    schema_type: :id,
    schema_table: :accounts,
    test_setup_helper: :sign_up_and_log_in_user
  ]

config :dirmoon,
  ecto_repos: [Dirmoon.Repo],
  llm_adapter: Dirmoon.LLM.NotConfigured,
  data_for_seo_adapter: Dirmoon.DataForSEO.NotConfigured,
  search_console_adapter: Dirmoon.SearchConsole.Client.NotConfigured,
  web_page_adapter: Dirmoon.WebPage.HTTP,
  price_check_page_limit: 5,
  grouping_phrase_limit: 400,
  serp_phrase_limit: 30,
  # Per-request USD prices for the estimate on the new research screen (unverified, see notes-dataforseo.md).
  cost_estimates: %{phrase_ideas: "0.09", search_volumes: "0.09", serp_top10: "0.002", llm_allowance: "0"},
  serp_max_age_days: 30,
  market_lists_max_age_days: 30,
  scoring_weights: %{volume: 0.4, cpc: 0.3, weakness: 0.3},
  generators: [timestamp_type: :utc_datetime]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  dirmoon: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :filter_parameters, ["password", "code"]
config :phoenix, :json_library, Jason

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  dirmoon: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
