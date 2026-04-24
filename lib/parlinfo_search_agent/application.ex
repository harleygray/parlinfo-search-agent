defmodule ParlInfoSearchAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    require Logger

    oban_config = Application.get_env(:parlinfo_search_agent, Oban, [])
    plugins = Keyword.get(oban_config, :plugins, [])

    cron_plugin =
      Enum.find(plugins, fn
        {Oban.Plugins.Cron, _} -> true
        _ -> false
      end)

    case cron_plugin do
      {Oban.Plugins.Cron, [crontab: crontab]} ->
        Logger.info("Oban Cron Plugin configured with #{length(crontab)} job(s):")

        Enum.each(crontab, fn {schedule, worker} ->
          Logger.info("  - #{schedule} → #{inspect(worker)}")
        end)

      _ ->
        Logger.warning(
          "Oban Cron Plugin not found in configuration - scheduled jobs will not run!"
        )
    end

    ParlInfoSearchAgent.ObanLogger.attach()

    children = [
      ParlInfoSearchAgentWeb.Telemetry,
      ParlInfoSearchAgent.Repo,
      {DNSCluster,
       query: Application.get_env(:parlinfo_search_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ParlInfoSearchAgent.PubSub},
      {Oban, Application.fetch_env!(:parlinfo_search_agent, Oban)},
      playwright_server_child(),
      ParlInfoSearchAgentWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ParlInfoSearchAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp playwright_server_child do
    if Application.get_env(:parlinfo_search_agent, :playwright_server_enabled, true) do
      ParlInfoSearchAgent.Scraper.PlaywrightServer
    else
      {Task, fn -> :ok end}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ParlInfoSearchAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
