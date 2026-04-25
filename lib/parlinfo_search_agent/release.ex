defmodule ParlInfoSearchAgent.Release do
  @app :parlinfo_search_agent

  @max_waf_retries 5

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def backfill_reports do
    {:ok, _} = Application.ensure_all_started(@app)
    IO.puts("Starting reports backfill (newest-first, all pages)...")
    backfill_reports_page(0, 0)
  end

  def backfill_transcripts do
    {:ok, _} = Application.ensure_all_started(@app)
    IO.puts("Starting hearing transcripts backfill (newest-first, all pages)...")
    backfill_transcripts_page(0, 0)
  end

  defp backfill_reports_page(page, total, waf_retries \\ 0)

  defp backfill_reports_page(_page, total, waf_retries) when waf_retries >= @max_waf_retries do
    IO.puts("Too many consecutive WAF blocks — giving up after #{total} items")
  end

  defp backfill_reports_page(page, total, waf_retries) do
    url =
      "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p" <>
        ";adv=yes;orderBy=date-eFirst;page=#{page};query=Dataset%3Areportjnt,reportsen,reportrep;resCount=100"

    IO.puts("Fetching page #{page}")

    case ParlInfoSearchAgent.Scraper.ParlinfoClient.scrape(url) do
      {:ok, []} ->
        IO.puts("Done — #{total} total items processed across #{page} pages")

      {:ok, items} ->
        new_count =
          Enum.count(items, fn item ->
            case ParlInfoSearchAgent.Items.upsert_report(item) do
              {:ok, :new, _} -> true
              _ -> false
            end
          end)

        IO.puts("  Page #{page}: #{length(items)} fetched, #{new_count} new")
        backfill_reports_page(page + 1, total + length(items), 0)

      {:error, :waf_blocked} ->
        IO.puts("  WAF block on page #{page} (#{waf_retries + 1}/#{@max_waf_retries}) — waiting 30s...")
        Process.sleep(30_000)
        backfill_reports_page(page, total, waf_retries + 1)

      {:error, reason} ->
        IO.puts("  Error on page #{page}: #{inspect(reason)} — stopping")
    end
  end

  defp backfill_transcripts_page(page, total, waf_retries \\ 0)

  defp backfill_transcripts_page(_page, total, waf_retries) when waf_retries >= @max_waf_retries do
    IO.puts("Too many consecutive WAF blocks — giving up after #{total} items")
  end

  defp backfill_transcripts_page(page, total, waf_retries) do
    url =
      "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p" <>
        ";adv=yes;orderBy=date-eFirst;page=#{page};query=Dataset%3Aestimate,comSen,comJoint,comRep;resCount=100"

    IO.puts("Fetching page #{page}")

    case ParlInfoSearchAgent.Scraper.ParlinfoClient.scrape(url) do
      {:ok, []} ->
        IO.puts("Done — #{total} total items processed across #{page} pages")

      {:ok, items} ->
        new_count =
          Enum.count(items, fn item ->
            case ParlInfoSearchAgent.Items.upsert_hearing_transcript(item) do
              {:ok, :new, _} -> true
              _ -> false
            end
          end)

        IO.puts("  Page #{page}: #{length(items)} fetched, #{new_count} new")
        backfill_transcripts_page(page + 1, total + length(items), 0)

      {:error, :waf_blocked} ->
        IO.puts("  WAF block on page #{page} (#{waf_retries + 1}/#{@max_waf_retries}) — waiting 30s...")
        Process.sleep(30_000)
        backfill_transcripts_page(page, total, waf_retries + 1)

      {:error, reason} ->
        IO.puts("  Error on page #{page}: #{inspect(reason)} — stopping")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
