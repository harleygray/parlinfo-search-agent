import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :parliament_search_agent, ParliamentSearchAgent.Repo,
  database: "parliament_search_agent_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :parliament_search_agent, ParliamentSearchAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "TIqCbwxVIbX6wQWgJG8TyWAqghj7mG1wnCwFcDOqhEBqUmiHd4cmIiIdArnCe2jg"
    ),
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :parliament_search_agent, Oban, testing: :inline

config :parliament_search_agent, :playwright_server_enabled, false

config :parliament_search_agent, :parlinfo_client, ParliamentSearchAgent.Scraper.MockParlinfoClient
config :parliament_search_agent, :parlview_client, ParliamentSearchAgent.Scraper.MockParlViewClient
