# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :parlinfo_search_agent,
  namespace: ParlInfoSearchAgent,
  ecto_repos: [ParlInfoSearchAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :parlinfo_search_agent, ParlInfoSearchAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ParlInfoSearchAgentWeb.ErrorHTML, json: ParlInfoSearchAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ParlInfoSearchAgent.PubSub,
  live_view: [signing_salt: "efFnHyIO"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :parlinfo_search_agent, Oban,
  repo: ParlInfoSearchAgent.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", ParlInfoSearchAgent.Workers.ReportsScraper},
       {"*/5 * * * *", ParlInfoSearchAgent.Workers.HearingTranscriptsScraper},
       {"*/5 * * * *", ParlInfoSearchAgent.Workers.BroadcastsScraper}
     ]}
  ],
  queues: [scraper: 3]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
