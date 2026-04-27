# Why Elixir: Architecture of Parliament Search Agent

## The core problem

This project does unreliable I/O against websites that are actively trying to block programmatic access. ParlInfo throws WAF blocks daily, response times vary, and the Playwright sidecar process is inherently fragile. The architecture has to tolerate that gracefully — scraper failures should be contained, recoverable, and invisible to users of the API and dashboard.

Elixir on the BEAM makes this a first-class concern rather than something you bolt on with libraries.

## Why the BEAM

The BEAM is the runtime Elixir compiles to. It was built for Erlang, which runs telecom infrastructure — systems that genuinely cannot go down. The properties it gives you are concurrency, failure recovery, and process isolation, baked in at the language level.

The fundamental model: the entire application is a tree of tiny, isolated processes. Processes don't share memory — they communicate by passing messages. Each process has a Supervisor watching it. When a process crashes, the Supervisor restarts it. The rest of the application never notices.

```
                  [ Supervisor ]
                        │
        "let it crash, restart, keep serving"
                        │
    ┌────────────┬──────┴──────┬─────────────────────┐
    ▼            ▼             ▼                     ▼
  [ Web ]    [ Repo ]    [ Oban jobs ]      [ Port → node.js ]
   API +      DB pool     scrapers,           Playwright,
   live                   backfills           walled off,
   dashboard                                  dies with the BEAM
```

For this project, that means scraper failures are contained. A WAF block that crashes a worker doesn't affect the API or the dashboard — those are separate processes under separate supervisors.

The secondary reason: this is adjacent to Civic Forum, which is also Elixir. Zero context switching.

## Architecture: what happens every 30 minutes

Oban schedules three jobs — one per dataset. Oban stores its state in Postgres, so you get retries, backoff, and history without any additional infrastructure. The three scrapers are staggered five minutes apart (Reports at :00/:30, Hearing Transcripts at :05/:35, Broadcasts at :10/:40) so the Playwright sidecar is never being hit by two scrapers simultaneously.

```
   Oban schedules 3 jobs   (durable, retried, stored in Postgres)
                  │
        ┌─────────┴──────────┬──────────────────┐
        ▼                    ▼                  ▼
     Reports             Hearings           Broadcasts
        └────────┬───────────┘                  │
                 ▼                              ▼
      [ Playwright sidecar ]          [ ParlView REST API ]
       Node + headless Chromium        the one source that
       walled off in its own            actually has an API
       supervised process
                 │                              │
                 └──────────────┬───────────────┘
                                ▼
                         [ Postgres ]
                       dedup + idempotent upsert
                                │
                ┌───────────────┴────────────────┐
                ▼                                ▼
          [ REST API ]                    [ Live Dashboard ]
          9 endpoints, no auth          updates pushed over
                                        WebSocket — no polling
```

Reports and hearing transcripts go through the Playwright sidecar — a headless Chromium instance driven by Node.js — because ParlInfo is a JavaScript-rendered app behind a WAF. Broadcasts come from ParlView, which has an actual REST API, so no scraping needed.

All results land in Postgres via idempotent upserts. The whole pipeline can be re-run mid-flight without creating duplicates or inconsistencies.

Two consumers read the same database: a public REST API with nine endpoints (no auth, no key), and a LiveView dashboard that pushes updates over WebSocket the moment a new row appears.

## The Playwright sidecar

The trickiest part of the architecture is the Playwright lifecycle.

Spinning up a browser per request is too slow — Chromium needs to stay running between scrapes. But a persistent Node.js process creates a supervision problem: if the BEAM restarts (deployment, crash, node bounce), you need the Node process to die with it. Orphaned Chromium processes are a real failure mode in production.

The solution is a `GenServer` called `PlaywrightServer` that opens the Node process via an Elixir `Port` using `spawn_executable` — no shell intermediary. The process tree is literally `BEAM → node`. When the BEAM exits, the port pipe closes, Node receives an EOF on stdin, and Chromium shuts down. No manual cleanup, no orphans.

On the WAF side: the Node server includes a stealth plugin to dodge fingerprint detection, plus explicit WAF detection. After `page.goto()`, it checks the page title for "WAF Block" (and checks for zero results combined with an "Azure WAF" title in CDN-proxied responses). On a block, it returns a typed `{"error": "waf_blocked"}` with HTTP 403 rather than an empty result set. The Elixir worker catches `:waf_blocked` and returns `{:snooze, 600}` — a 10-minute delay — rather than `{:error, reason}`, which would burn Oban retry attempts on an unrecoverable transient condition.

The important thing here: a WAF block is a typed result, not a crash. The worker handles it deliberately, the supervision tree is never involved, and nothing downstream is affected.

## Oban, idempotency, and LiveView

**Oban** stores job state in Postgres. Every job has a record: when it ran, what it returned, whether it's pending, snoozed, or completed. The visibility is useful operationally, and Postgres-backed persistence means jobs survive application restarts.

**Idempotency** is load-bearing. ParlInfo returns one search result per section of a document, so a 14-chapter report shows up as 14 rows in the search results. The upsert collapses them by document ID — each scrape run is safe to repeat. This matters for backfills (which can be interrupted and re-run) and for the WAF snooze behaviour (which retries the same page).

**LiveView and PubSub** close the loop between the database and the dashboard. When a new record is inserted, the context module broadcasts a PubSub event. The LiveView dashboard subscribes at mount and prepends the new row in place. There's no polling on the client and no periodic refresh on the server — the push happens the moment the row exists.

## The backfill problem in production

The original backfill ran as a recursive loop, firing a Playwright request every five seconds with no pause between pages. This worked locally (dev traffic doesn't go through the Azure WAF path) but the WAF rate-limited it in production hard enough to crash Chromium mid-run.

A secondary issue: pages proxied through the Azure CDN have the title "Azure WAF" even for legitimate results. A soft WAF block (zero results, no "WAF Block" title) was being misread as end-of-pagination, causing the backfill to stop early.

The fix was to redesign backfills as Oban worker chains. Each job fetches one page and enqueues the next with a five-second `schedule_in` delay. WAF blocks snooze the job for ten minutes rather than retrying immediately. The chain runs inside the normal Oban scheduler — one job at a time in the scraper queue — which gives you progress visibility in Oban's job history and makes the whole thing safe to interrupt and restart.

`fly ssh console` → `eval "ParliamentSearchAgent.Release.backfill_reports()"` inserts one job and returns immediately. The running app's Oban picks it up and drives the rest of the chain. The `eval` command doesn't need to stay connected.
