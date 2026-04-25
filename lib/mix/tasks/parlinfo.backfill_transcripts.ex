defmodule Mix.Tasks.Parlinfo.BackfillTranscripts do
  use Mix.Task

  @shortdoc "Backfill all hearing transcripts from ParlInfo"

  @max_waf_retries 5

  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Scraper.ParlinfoClient

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    IO.puts("Starting hearing transcripts backfill (newest-first, all pages)...")
    backfill(0, 0)
  end

  defp page_url(page) do
    "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p" <>
      ";adv=yes;orderBy=date-eFirst;page=#{page};query=Dataset%3Aestimate,comSen,comJoint,comRep;resCount=100"
  end

  defp backfill(page, total, waf_retries \\ 0)

  defp backfill(_page, total, waf_retries) when waf_retries >= @max_waf_retries do
    IO.puts("Too many consecutive WAF blocks — giving up after #{total} items")
  end

  defp backfill(page, total, waf_retries) do
    url = page_url(page)
    IO.puts(link("Fetching page #{page}", url))

    case ParlinfoClient.scrape(url) do
      {:ok, []} ->
        IO.puts("Done — #{total} total items processed across #{page} pages")

      {:ok, items} ->
        new_count =
          Enum.count(items, fn item ->
            case Items.upsert_hearing_transcript(item) do
              {:ok, :new, _} -> true
              _ -> false
            end
          end)

        IO.puts("  Page #{page}: #{length(items)} fetched, #{new_count} new")
        backfill(page + 1, total + length(items), 0)

      {:error, :waf_blocked} ->
        IO.puts("  WAF block on page #{page} (#{waf_retries + 1}/#{@max_waf_retries}) — waiting 30s before retry...")
        Process.sleep(30_000)
        backfill(page, total, waf_retries + 1)

      {:error, reason} ->
        IO.puts("  Error on page #{page}: #{inspect(reason)} — stopping")
    end
  end

  defp link(text, url), do: "\e]8;;#{url}\a#{text}\e]8;;\a"
end
