import Config

alias Dirmoon.DataForSEO.HTTP
alias Dirmoon.LLM.OpenAI
alias Dirmoon.SearchConsole.Client.Google

# In test we don't send emails
config :dirmoon, Dirmoon.Mailer, adapter: Swoosh.Adapters.Test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dirmoon, Dirmoon.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dirmoon_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dirmoon, DirmoonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Q4g8AbduLqSSlbzbFV0/whHt+kA3lyPWxFBTXXEDex3APJ4Ts3PxsW7wBb9Kx479",
  server: false

config :dirmoon, Google,
  client_id: "test-google-client-id",
  client_secret: "test-google-client-secret",
  req_options: [plug: {Req.Test, Google}]

config :dirmoon, HTTP,
  login: "test-dataforseo-login",
  password: "test-dataforseo-password",
  req_options: [plug: {Req.Test, HTTP}]

config :dirmoon, Oban, testing: :manual

config :dirmoon, OpenAI,
  api_key: "test-openai-key",
  req_options: [plug: {Req.Test, OpenAI}]

config :dirmoon,
  llm_adapter: Dirmoon.LLMMock,
  data_for_seo_adapter: Dirmoon.DataForSEOMock,
  search_console_adapter: Dirmoon.SearchConsoleMock

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
