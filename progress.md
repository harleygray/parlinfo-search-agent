# v0.1.1 Progress

## WAF Detection

**Problem:** The Playwright scraper was silently returning 0 items when parlinfo.aph.gov.au returned a WAF block page (HTTP 403). There was no way to distinguish a genuine empty result from a block.

**Changes:**

- `playwright_server/server.js` — after `page.goto()` in both `/scrape` and `/scrape_item`, checks the page title for "WAF Block". Returns `{"error": "waf_blocked"}` with HTTP 403 instead of proceeding.
- `lib/parliament_search_agent/scraper/parlinfo_client.ex` — added pattern match for the `403 waf_blocked` response in both `scrape/1` and `scrape_item/2`, returning `{:error, :waf_blocked}`.
- `lib/parliament_search_agent/workers/reports_scraper.ex` and `hearing_transcripts_scraper.ex` — WAF blocks now trigger `{:snooze, 600}` (10-minute delay) rather than `{:error, reason}`, which would burn Oban retry attempts.

## Backfill Mix Tasks

Two new mix tasks for populating historical records.

**`mix parlinfo.backfill_reports`** and **`mix parlinfo.backfill_transcripts`**

- Paginate ParlInfo using `orderBy=date-eFirst` (newest first), 100 results per page
- Upsert each item into the database, stop when ParlInfo returns an empty page
- On WAF block: wait 30 seconds and retry the same page
- Detail scraping (PDF URLs, committee metadata) is intentionally skipped during backfill to avoid triggering WAF on thousands of individual page loads. Detail fields are filled in subsequently by the `DetailBackfillWorker` cron job.
- ParlInfo data goes back to ~2016; the full backfill is ~111 pages (~11,000 records) for reports

Files: `lib/mix/tasks/parlinfo.backfill_reports.ex`, `lib/mix/tasks/parlinfo.backfill_transcripts.ex`

**Running the tasks:**

Locally (against dev database):
```bash
mix parlinfo.backfill_reports
mix parlinfo.backfill_transcripts
```

On Fly.io (against production database):
```bash
fly ssh console
mix parlinfo.backfill_reports
mix parlinfo.backfill_transcripts
```

Run them sequentially — both tasks share the same Playwright server and parallel runs increase WAF block risk. Each task prints a line per page fetched and will print a final count when ParlInfo returns an empty page. If the SSH session drops mid-run it is safe to re-run — all upserts are idempotent and already-inserted records are skipped.

## Detail Backfill Worker

**Problem:** The backfill mix tasks populate catalogue records (title, date, source URL) but intentionally skip detail scraping to avoid WAF blocks during bulk runs. This left `pdf_url`, `committee_name`, and other metadata fields nil indefinitely — the regular scrapers only call `scrape_item_detail` on records that arrive as `:new` in the current page fetch, so backfilled records (which appear as `:existing`) were never enriched.

**Solution:** `DetailBackfillWorker` — a new Oban worker that runs every 30 minutes and enriches records missing `pdf_url`.

**Behaviour:**

- Queries up to 25 reports + 25 hearing transcripts where `pdf_url IS NULL`, ordered by `date_tabled DESC NULLS LAST` (most recent first, as those are most likely to be queried)
- For each record, calls the existing `scrape_item(source_url, dataset)` → `update_report/update_hearing_transcript` pipeline — no new scraping infrastructure needed
- WAF block at any point → `{:snooze, 600}`, abandons the current batch and retries after 10 minutes
- When no records are missing → logs "nothing to do" and exits immediately

File: `lib/parliament_search_agent/workers/detail_backfill_worker.ex

## Live-Feed Pagination

**Problem:** The dashboard feed loaded a fixed 50 items with no way to browse further once the database grew large.

**Changes:**

- Each dataset (reports, hearing_transcripts, broadcasts) now has its own page counter in socket assigns (`reports_page`, `transcripts_page`, `broadcasts_page`) and a corresponding `total_pages` count.
- Data loading switched from `Items.get_latest/2` to `Items.list_items/1` with `per_page: 50`.
- Prev/Next pagination bar added below each table.
- PubSub new-item prepending only fires when on page 1 for that dataset.
- The 30-second refresh reloads the current page for all three datasets and updates total_pages.

File: `lib/parliament_search_agent_web/live/dashboard_live.ex`

## Query Ordering Fix

**Problem:** After the backfill ran, the live feed and API were showing oldest records first. The backfill inserts records newest-first (page 0 = 2025, page 111 = 2016), so the oldest parliamentary records ended up with the most recent `inserted_at` timestamps in the database. Ordering by `inserted_at DESC` therefore surfaced 2016 records at the top.

**Fix:** `Items.list_items/1` now orders by `date_tabled DESC NULLS LAST` (with `inserted_at DESC` as tiebreaker) for reports and transcripts, and by `start_time DESC NULLS LAST` for broadcasts. This reflects parliamentary date rather than database insertion order.

API documentation updated to reflect correct ordering:
- `/api/reports` and `/api/hearing_transcripts` — descriptions now state "ordered by date tabled (most recent first)"
- `/api/broadcasts/latest` — corrected from "Most recently inserted" to "Most recent by start time"

Files: `lib/parliament_search_agent/items.ex`, `lib/parliament_search_agent_web/live/dashboard_live.ex`

## Sticky Table Headers

`thead th` elements are now `position: sticky; top: 0; z-index: 1` so the header row stays visible when scrolling through long result sets.

File: `priv/static/assets/css/app.css`

## API / Ecto Consistency Tests

New `describe "API matches Ecto query"` block added to all three controller test files. Each adds two tests:

1. **Paginated results** — calls the API with `page=1&per_page=3` and `Items.list_items/1` with the same params, asserts the sorted ID sets match exactly.
2. **Date-filtered results** — inserts records spanning different years, filters by `from=`, asserts API and Ecto return the same records.

This catches any divergence between the controller serialisation layer and the underlying query logic.

Files: `test/parliament_search_agent_web/controllers/api/reports_controller_test.exs`, `hearing_transcripts_controller_test.exs`, `broadcasts_controller_test.exs`

## Worker Schedule (updated)

All scrapers moved from every 5 minutes to every 30 minutes, staggered at 5-minute intervals to avoid simultaneous Playwright page loads hitting the same remote host.


| Minutes past the hour | Worker                      |
| ----------------------- | ----------------------------- |
| :00, :30              | `ReportsScraper`            |
| :05, :35              | `HearingTranscriptsScraper` |
| :10, :40              | `BroadcastsScraper`         |
| :15, :45              | `DetailBackfillWorker`      |

The backfill mix tasks, regular scrapers, and detail backfill worker now form a complete pipeline:

1. **`mix parlinfo.backfill_*`** — bulk-loads catalogue records (title, date, source URL) going back to 2020
2. **`ReportsScraper` / `HearingTranscriptsScraper`** — keeps the catalogue current with new items every 30 minutes
3. **`DetailBackfillWorker`** — progressively enriches records missing `pdf_url` and metadata, 50 at a time

File: `config/config.exs`

## Livebook Integration

**Purpose:** Interactive data inspection and transformation for large backfilled datasets.

**Setup:**

- Added `{:kino, "~> 0.19", only: :dev}` to `mix.exs`
- `mix parlinfo.livebook` — prints the two commands needed to start the app as a named Erlang node and launch Livebook with `LIVEBOOK_DEFAULT_RUNTIME` pre-configured for the attached node runtime
- `priv/notebooks/backfill_analysis.livemd` — notebook with sections for dataset overview, year-by-year distribution, missing PDF URL audit, recent records, and a free-form query cell

**Connection method:** Livebook uses the Attached node runtime. The app must be started with a named node so Livebook can connect via distributed Erlang:

```bash
# Terminal 1
iex --name parlinfo@127.0.0.1 --cookie livebook_dev -S mix

# Terminal 2
LIVEBOOK_DEFAULT_RUNTIME="attached:parlinfo@127.0.0.1:livebook_dev" livebook server --port 4040
```

Files: `lib/mix/tasks/parlinfo.livebook.ex`, `priv/notebooks/backfill_analysis.livemd`

## Anti-Pattern Remediation (post-backfill review)

A senior Elixir developer review of all v0.1.1 changes surfaced the following issues, all fixed before the v0.1.1 commit:

**`lib/parliament_search_agent/workers/detail_backfill_worker.ex`**
- Added `else (other -> other)` to the `with` in `perform/1`. Without it, `{:snooze, 600}` returned by `process_batch` was implicitly passed through, which works but is invisible to a reader.

**`lib/parliament_search_agent_web/live/dashboard_live.ex`**
- Moved `require Logger` from inside the `handle_event("run_worker", ...)` body to the module level, consistent with all other modules.
- Extracted a `<.paginated_table>` function component (slot-based) to replace the three identical wrapper + pagination-bar blocks for reports, transcripts, and broadcasts. Eliminates ~75 lines of duplicate HEEx.

**`lib/parliament_search_agent/items.ex`**
- Fixed `merge_all/2` sort key from `inserted_at` (a database insertion timestamp) to the parliamentary date (`date_tabled` / `start_time`), matching the per-dataset ordering used in `list_items/1`. Added private `item_sort_date/1` helper that normalises to ISO-8601 strings for comparison.

**`lib/mix/tasks/parlinfo.backfill_reports.ex` and `parlinfo.backfill_transcripts.ex`**
- Added a `@max_waf_retries 5` cap and a `waf_retries` counter to `backfill/3`. The retry counter resets to 0 on a successful page fetch and the task gives up (with a clear message) after 5 consecutive WAF blocks on the same page.
- Replaced `@base_url` + `String.replace(@base_url, "PAGE", ...)` with a `page_url/1` function that interpolates the page number directly into the URL string, removing the fragile placeholder substitution.

**`playwright_server/server.js`**
- Passed `DIAGNOSTICS_ENABLED` as an argument into `page.evaluate()` and gated all three expensive DOM queries (`querySelectorAll("a[href]")`, `container.innerHTML`, `container.children`) behind the flag. Previously these ran on every scrape even when diagnostics were disabled.

Files: all files listed above.

## Backfill as Oban Worker Chain

**Problem:** The original backfill (`Release.backfill_reports/0`) ran as a continuous recursive loop, firing a Playwright request every ~5 seconds with no pause between pages. The Azure WAF rate-limits this pattern in production, causing Chromium to crash mid-run with `"Execution context was destroyed, most likely because of a navigation"`. The mix tasks worked in dev because dev traffic doesn't go through the same WAF path.

A secondary issue: pages served via the Azure CDN in production have the title `"Azure WAF"` even for legitimate results. When the WAF soft-blocks a page (returning 0 results but not a "WAF Block" title), the scraper was interpreting it as end-of-pagination and stopping early.

**Changes:**

- `playwright_server/server.js` — added a check: if `diag.rowCount === 0` AND `pageTitle.includes("Azure WAF")`, return `waf_blocked` (403) rather than an empty items array. This distinguishes a soft WAF block from genuine end-of-pagination.
- `lib/parliament_search_agent/workers/backfill_reports_worker.ex` — new Oban worker. Takes `%{"page" => page, "total" => total}` as job args. Fetches one page, upserts items, then enqueues the next page job with `schedule_in: 5`. WAF block → `{:snooze, 600}`. Empty page → logs completion and stops.
- `lib/parliament_search_agent/workers/backfill_transcripts_worker.ex` — same for hearing transcripts.
- `lib/parliament_search_agent/release.ex` — `backfill_reports/0` and `backfill_transcripts/0` now insert a single Oban job via `Ecto.Migrator.with_repo` (starts only the Repo, not full Oban) and return immediately. The running app's Oban picks up the job and drives the chain.
- `config/config.exs` — reduced `scraper` queue concurrency from 3 to 1, ensuring only one Playwright-using worker runs at a time.

**Running in production:**

```bash
fly ssh console --app parliament-search-agent
/app/bin/parliament_search_agent eval "ParliamentSearchAgent.Release.backfill_reports()"
# monitor: fly logs --app parliament-search-agent | grep backfill_reports
# after reports done:
/app/bin/parliament_search_agent eval "ParliamentSearchAgent.Release.backfill_transcripts()"
```

**Running in dev:**

```bash
mix parlinfo.backfill_reports
mix parlinfo.backfill_transcripts
```

The mix tasks still exist for dev use (inline loop, no Oban dependency). They work fine locally where the Azure WAF is not in the path.
