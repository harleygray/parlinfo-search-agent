defmodule ParliamentSearchAgent.Workers.DetailBackfillWorker do
  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger

  import Ecto.Query

  alias ParliamentSearchAgent.{Repo, Items}
  alias ParliamentSearchAgent.Items.{Report, HearingTranscript}

  @batch_size 25

  @client Application.compile_env(
            :parliament_search_agent,
            :parlinfo_client,
            ParliamentSearchAgent.Scraper.ParlinfoClient
          )

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    reports = missing_detail(Report, @batch_size)
    transcripts = missing_detail(HearingTranscript, @batch_size)

    if reports == [] and transcripts == [] do
      Logger.info("[detail_backfill] No records missing detail — nothing to do")
      :ok
    else
      Logger.info("[detail_backfill] Processing #{length(reports)} reports, #{length(transcripts)} transcripts")

      with :ok <- process_batch(reports, "reports", &Items.update_report/2),
           :ok <- process_batch(transcripts, "hearing_transcripts", &Items.update_hearing_transcript/2) do
        Logger.info("[detail_backfill] Done")
        :ok
      else
        other -> other
      end
    end
  end

  defp missing_detail(schema, limit) do
    Repo.all(
      from r in schema,
        where: is_nil(r.pdf_url),
        order_by: [desc_nulls_last: r.date_tabled],
        limit: ^limit
    )
  end

  defp process_batch([], _dataset, _update_fn), do: :ok

  defp process_batch([record | rest], dataset, update_fn) do
    case @client.scrape_item(record.source_url, dataset) do
      {:ok, detail} ->
        case update_fn.(record, detail) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[detail_backfill] Failed to update #{record.parlinfo_id}: #{inspect(reason)}"
            )
        end

        process_batch(rest, dataset, update_fn)

      {:error, :waf_blocked} ->
        Logger.warning("[detail_backfill] WAF block — snoozing 10 minutes")
        {:snooze, 600}

      {:error, reason} ->
        Logger.warning(
          "[detail_backfill] scrape_item failed for #{record.parlinfo_id}: #{inspect(reason)}"
        )

        process_batch(rest, dataset, update_fn)
    end
  end
end
