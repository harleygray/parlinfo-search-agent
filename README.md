# ParlInfo Search Agent

A self-hosted data bridge for the Australian Parliament's public archive. It continuously scrapes [ParlInfo](https://parlinfo.aph.gov.au/) and the ParlView broadcast API, deduplicates and stores results in PostgreSQL, and exposes them via a typed JSON REST API — with a real-time LiveView dashboard for monitoring.

## What Problem Does This Solve?

ParlInfo is the Australian Parliament's searchable archive of parliamentary documents: committee reports, hearing transcripts, tabled papers, and more. It's a rich public dataset, but it has **no public API**. The search interface is a JavaScript-rendered web application, meaning a plain HTTP request returns an empty page; the actual results only exist after the browser executes client-side scripts.

This project bridges that gap:

1. A headless browser (Playwright + stealth) loads ParlInfo search result pages in full
2. Results are parsed, deduplicated, and stored in a structured Postgres database
3. A clean JSON REST API serves the stored data to downstream consumers
4. A Phoenix LiveView dashboard lets you watch new items arrive in real time

An immediate downstream consumer is [Civic Forum](https://civicforum.com.au), which uses this cleaned parliamentary data for AI workflows. The API is designed to be generic enough for any consumer of this information.

---

## Datasets Covered


| Dataset                 | Source            | Description                                                                                                                                             |
| ------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Committee Reports**   | ParlInfo scraper  | Reports from joint, Senate, and House committees — one row per document, with title, committee name, inquiry name, tabled/referred dates, and PDF link |
| **Hearing Transcripts** | ParlInfo scraper  | Estimates hearings and committee proceedings — title, committee, date, parliament number, and PDF link                                                 |
| **Broadcasts**          | ParlView REST API | Live and archived parliamentary TV recordings — title, chamber, start time, duration, and direct ParlView link                                         |

Reports and hearing transcripts are scraped every 15 minutes. Broadcasts are pulled from the ParlView API, which returns the 100 most recent committee recordings and updates live/ended status on subsequent runs.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Phoenix / OTP Application               │
│                                                         │
│   Oban Cron (15min)                                     │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
│   │ReportsScraper│  │HearingScraper│  │BroadcastsSc.│  │
│   └──────┬───────┘  └──────┬───────┘  └──────┬──────┘  │
│          │                 │                  │         │
│          ▼                 ▼                  ▼         │
│   ParlinfoClient     ParlinfoClient    ParlViewClient   │
│   (HTTP → Node.js)   (HTTP → Node.js)  (HTTP → APH)    │
│          │                 │                            │
│          ▼                 ▼                            │
│   ┌──────────────────────────────┐                      │
│   │  PlaywrightServer (GenServer)│                      │
│   │  Elixir Port → node server.js│                      │
│   │  Chromium (stealth mode)     │                      │
│   └──────────────────────────────┘                      │
│                                                         │
│   Items context (Ecto)  →  PostgreSQL                   │
│   REST API (9 endpoints)                                │
│   LiveView Dashboard (PubSub real-time updates)         │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

**Elixir/Phoenix + OTP** — the scrape pipeline runs as supervised background workers under Oban. If a worker crashes, OTP restarts it cleanly without touching the web server or other workers.

**Playwright sidecar (Node.js)** — ParlInfo's search results are rendered client-side. Rather than embedding Playwright via a NIF or spawning a browser per request, a persistent Express HTTP server (`playwright_server/server.js`) keeps a single warm Chromium instance and accepts `POST /scrape` requests from Elixir. This avoids cold-start latency on every job.

**playwright-extra stealth plugin** — ParlInfo blocks naive headless Chrome fingerprints. The stealth plugin patches the browser's JavaScript environment (navigator, WebGL, etc.) to look like a real user session.

**Elixir Port for process lifecycle** — the `PlaywrightServer` GenServer opens the Node.js process via an Elixir Port using `spawn_executable` (not a shell), so the process chain is BEAM → node with no intermediate shell. When the BEAM shuts down, the port pipe closes, which triggers graceful Chromium shutdown. There is no orphan node process.

**Oban for job scheduling** — durable job storage in Postgres, built-in retry/backoff on failure, visible job history, and Cron-based scheduling. Completed jobs are pruned after 24 hours.

**Upsert-by-document-ID** — ParlInfo returns one search result per *section* of a document (a 14-chapter report produces 14 entries sharing the same PDF and metadata). The scraper collapses these into one row per document, storing the document-level `parlinfo_id` and an array of all seen section IDs. Scrape runs are fully idempotent.

**Two-pass scraping** — after a new document is inserted from search results (which contain summary metadata), a second browser pass navigates to the item's detail page to extract richer fields: PDF URL, committee name, chamber, inquiry name, tabling and referral dates, and the canonical ParlInfo permalink.

**PubSub real-time updates** — new items and detail-scrape completions both broadcast PubSub events. The LiveView dashboard subscribes at mount and updates individual rows in-place within seconds, without any polling or page reload.

---

## REST API

Nine endpoints across three datasets. No authentication required.

### Reports

```
GET /api/reports                   # paginated list; supports ?from=YYYY-MM-DD&to=YYYY-MM-DD&page=N&per_page=N
GET /api/reports/latest            # most recent N reports (default 20, max 100)
GET /api/reports/:id               # single report by UUID
```

Example response (`/api/reports/latest`):

```json
{
  "items": [
    {
      "id": "550e8400-...",
      "parlinfo_ids": ["committees/reportsen/RB000778/0000", "committees/reportsen/RB000778/0001"],
      "title": "Funding and Resourcing for the CSIRO",
      "committee_name": "Environment and Communications References Committee",
      "inquiry_name": "CSIRO Funding",
      "date_tabled": "2026-04-15T00:00:00",
      "date_referred": "2025-11-26T12:00:00",
      "report_type": "Final",
      "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/...",
      "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Freportsen%2FRB000778%2F0000%22"
    }
  ],
  "page": 1,
  "per_page": 20,
  "total": 47
}
```

### Hearing Transcripts

```
GET /api/hearing_transcripts       # paginated list; same date filters
GET /api/hearing_transcripts/latest
GET /api/hearing_transcripts/:id
```

### Broadcasts

```
GET /api/broadcasts                # paginated list; date range filters on start_time
GET /api/broadcasts/latest
GET /api/broadcasts/:id
```

Example broadcast item:

```json
{
  "id": "...",
  "parlview_id": "12345",
  "title": "Senate Standing Committee on Economics",
  "chamber": "Senate - Committee",
  "is_live": false,
  "start_time": "2026-04-20T09:05:00",
  "duration": "08:40:00",
  "source_url": "https://www.aph.gov.au/News_and_Events/Watch_Read_Listen/ParlView/video/12345"
}
```

---

## LiveView Dashboard

Served at `/`, the dashboard has two tabs visible in the navbar:

**Live Feed** — three sub-tabs (Reports / Hearing Transcripts / Broadcasts). All data is loaded at mount and updated live via PubSub; switching tabs is instant. Each dataset has a tailored table with columns relevant to that type. A PDF icon links directly to the document PDF when available; a ParlInfo or ParlView icon links to the source page.

**API Reference** — inline documentation for all nine endpoints. Each endpoint is a collapsed-by-default accordion showing parameter definitions, an example request URL, and a full example response JSON.

## Tech Stack


| Layer              | Technology                                        |
| -------------------- | --------------------------------------------------- |
| Language           | Elixir                                            |
| Web framework      | Phoenix + Phoenix LiveView                        |
| Database           | PostgreSQL (via Ecto + Postgrex)                  |
| Background jobs    | Oban                                              |
| Browser automation | Playwright (Node.js sidecar via Elixir Port)      |
| Stealth            | playwright-extra + puppeteer-extra-plugin-stealth |
| HTTP client        | Req                                               |
| Test mocking       | Mox                                               |
| Deployment         | Fly.io (Docker)                                   |

---

## Local Setup

### Prerequisites

- Elixir 1.15+, Erlang/OTP 26+
- Node.js 18+ (for the Playwright sidecar)
- PostgreSQL 15+

### Steps

**1. Clone and install dependencies**

```bash
git clone https://github.com/harleygray/parlinfo-search-agent
cd parlinfo-search-agent
mix deps.get
```

**2. Configure the database**

Copy `.env.example` to `.env` and set your database URL:

```bash
cp .env.example .env
# Edit .env — set DATABASE_URL=ecto://user:password@localhost/parlinfo_dev
```

**3. Create and migrate the database**

```bash
mix ecto.setup
```

**4. Install Playwright and its browser**

```bash
cd playwright_server
npm install
npx playwright install chromium
cd ..
```

**5. Start the server**

```bash
mix phx.server
```

The Phoenix app starts on `http://localhost:4002`. The Playwright server starts automatically as a supervised GenServer on port 4003. Oban workers begin running on their 15-minute cron schedule; the first scrape runs on startup.

### Useful commands

```bash
# Wipe all scraped data (reports, hearing transcripts, broadcasts)
mix parlinfo.clear_items

# Run the test suite
mix test

# Run the full pre-commit check (compile, format, unused deps, tests)
mix precommit
```

---

## Planned Improvements

- **Webhook subscriptions** — `POST /api/webhook/subscribe` with Oban-backed delivery and retry
- **Additional datasets** — Hansard debates, Bills, Answers to Questions on Notice

---

## Project Status

The scraping pipeline, deduplication logic, REST API, and LiveView dashboard are all complete and in production. The project is deployed to Fly.io and continuously polling parliamentary activity.
