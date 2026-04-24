defmodule ParlInfoSearchAgent.Workers.HearingTranscriptsScraper do
  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger

  alias ParlInfoSearchAgent.Items

  @url "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p;adv=yes;orderBy=date-eFirst;page=0;query=Dataset%3Aestimate,comSen,comJoint,comRep;resCount=100"
  @dataset "hearing_transcripts"

  @client Application.compile_env(
            :parlinfo_search_agent,
            :parlinfo_client,
            ParlInfoSearchAgent.Scraper.ParlinfoClient
          )

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[#{@dataset}] Starting scrape")

    with {:ok, items} <- @client.scrape(@url) do
      Logger.info("[#{@dataset}] Scraper returned #{length(items)} items")

      {new_count, existing_count} =
        Enum.reduce(items, {0, 0}, fn item, {new, existing} ->
          case Items.upsert_hearing_transcript(item) do
            {:ok, :new, transcript} ->
              scrape_item_detail(transcript)
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
      {:error, reason} ->
        Logger.error("[#{@dataset}] Scrape failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp scrape_item_detail(transcript) do
    case @client.scrape_item(transcript.source_url, @dataset) do
      {:ok, detail} ->
        case Items.update_hearing_transcript(transcript, detail) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[#{@dataset}] Failed to update detail for #{transcript.parlinfo_id}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.warning(
          "[#{@dataset}] Detail scrape failed for #{transcript.parlinfo_id}: #{inspect(reason)}"
        )
    end
  end
end
