defmodule ParliamentSearchAgent.Workers.BackfillTranscriptsWorker do
  use Oban.Worker, queue: :scraper, max_attempts: 5

  require Logger

  alias ParliamentSearchAgent.Items
  alias ParliamentSearchAgent.Scraper.ParlinfoClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"page" => page, "total" => total}}) do
    url =
      "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p" <>
        ";adv=yes;orderBy=date-eFirst;page=#{page};query=Dataset%3Aestimate,comSen,comJoint,comRep;resCount=100"

    Logger.info("[backfill_transcripts] Fetching page #{page}")

    case ParlinfoClient.scrape(url) do
      {:ok, []} ->
        Logger.info("[backfill_transcripts] Done — #{total} total items across #{page} pages")
        :ok

      {:ok, items} ->
        new_count =
          Enum.count(items, fn item ->
            match?({:ok, :new, _}, Items.upsert_hearing_transcript(item))
          end)

        Logger.info(
          "[backfill_transcripts] Page #{page}: #{length(items)} fetched, #{new_count} new"
        )

        {:ok, _} =
          Oban.insert(__MODULE__.new(%{page: page + 1, total: total + length(items)}, schedule_in: 5))

        :ok

      {:error, :waf_blocked} ->
        Logger.warning("[backfill_transcripts] WAF block on page #{page} — snoozing 10 minutes")
        {:snooze, 600}

      {:error, reason} ->
        Logger.error("[backfill_transcripts] Error on page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
