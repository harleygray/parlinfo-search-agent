defmodule ParliamentSearchAgent.Workers.ReportsScraper do
  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger

  alias ParliamentSearchAgent.Items

  @url "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p;adv=yes;orderBy=date-eFirst;page=0;query=Dataset%3Areportjnt,reportsen,reportrep;resCount=100"
  @dataset "reports"

  @client Application.compile_env(
            :parliament_search_agent,
            :parlinfo_client,
            ParliamentSearchAgent.Scraper.ParlinfoClient
          )

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[#{@dataset}] Starting scrape")

    with {:ok, items} <- @client.scrape(@url) do
      Logger.info("[#{@dataset}] Scraper returned #{length(items)} items")

      {new_count, existing_count} =
        Enum.reduce(items, {0, 0}, fn item, {new, existing} ->
          case Items.upsert_report(item) do
            {:ok, :new, report} ->
              scrape_item_detail(report)
              {new + 1, existing}

            {:ok, :existing} ->
              {new, existing + 1}

            {:error, reason} ->
              Logger.error(
                "[#{@dataset}] Failed to upsert #{item["parlinfo_id"]}: #{inspect(reason)}"
              )

              {new, existing + 1}
          end
        end)

      Logger.info("[#{@dataset}] Done — #{new_count} new, #{existing_count} already existed")
      :ok
    else
      {:error, :waf_blocked} ->
        Logger.warning("[#{@dataset}] WAF block — snoozing job for 10 minutes")
        {:snooze, 600}

      {:error, reason} ->
        Logger.error("[#{@dataset}] Scrape failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp scrape_item_detail(report) do
    case @client.scrape_item(report.source_url, @dataset) do
      {:ok, detail} ->
        case Items.update_report(report, detail) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[#{@dataset}] Failed to update detail for #{report.parlinfo_id}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.warning(
          "[#{@dataset}] Detail scrape failed for #{report.parlinfo_id}: #{inspect(reason)}"
        )
    end
  end
end
