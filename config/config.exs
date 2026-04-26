# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :parliament_search_agent,
  namespace: ParliamentSearchAgent,
  ecto_repos: [ParliamentSearchAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :parliament_search_agent, ParliamentSearchAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ParliamentSearchAgentWeb.ErrorHTML, json: ParliamentSearchAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ParliamentSearchAgent.PubSub,
  live_view: [signing_salt: "efFnHyIO"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :parliament_search_agent, Oban,
  repo: ParliamentSearchAgent.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    {Oban.Plugins.Cron,
     crontab: [
       {"0,30 * * * *", ParliamentSearchAgent.Workers.ReportsScraper},
       {"5,35 * * * *", ParliamentSearchAgent.Workers.HearingTranscriptsScraper},
       {"10,40 * * * *", ParliamentSearchAgent.Workers.BroadcastsScraper},
       {"15,45 * * * *", ParliamentSearchAgent.Workers.DetailBackfillWorker}
     ]}
  ],
  queues: [scraper: 1]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
