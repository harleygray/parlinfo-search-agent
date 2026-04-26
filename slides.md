# ParlInfo Search Agent — Launch Video

**Target length:** ~3 minutes total. ~60s overview + ~2 min technical.
**Format:** PiP — webcam of you over the PC screen. Slides act as B-roll / reference behind you when you're not on the live app.

Each section has a slide (what's on screen / behind you) and rough talking-point bullets. Bullets are spoken-style notes, not a script — riff off them, don't read them.

---

## PART 1 — OVERVIEW (~60 seconds)

The job here is: land the problem, prove it works, close with a call to action. No backstory.

---

### Slide 1 — Title (5s)

**On screen:** Slide behind you.

```
ParlInfo Search Agent
A clean API for Australian parliamentary data
```

**Talk:**
- "I built a public API for the Australian Parliament's archive."
- "If you've ever tried to programmatically pull a hearing transcript or a committee report — you'll know why this exists."

---

### Slide 2 — The Problem (~15s)

**On screen:** Switch to live `parlinfo.aph.gov.au` in browser. Search for something. Open DevTools → Network tab. Show that the initial HTML response is empty / missing the results.

**Talk:**
- "ParlInfo is the public archive — committee reports, hearing transcripts, broadcasts. All free, all public."
- "But there's no API. The search interface is a JavaScript app, so a normal HTTP request gets you back a basically empty page."
- "If you want this data programmatically, you've got to drive a real browser. It's annoying. I've been working around it for years."

---

### Slide 3 — The Solution, Live (~25s)

**On screen:** Switch to your deployed dashboard. Walk through:
1. The Live Feed tab — point at fresh items arriving (mention they update via PubSub, no refresh needed).
2. Click a PDF icon → real PDF opens.
3. Click the API Reference tab → expand `/api/reports/latest` → show the example JSON.
4. Open a new tab, paste the actual live URL (`https://<your-domain>/api/reports/latest`), show real JSON returned.

**Talk:**
- "So this is what I built. It runs a headless browser in the background, scrapes ParlInfo every 30 minutes, deduplicates, and stores everything in Postgres."
- "Live feed updates in real time as new items come in." *(point at the table)*
- "Nine REST endpoints across three datasets — reports, hearing transcripts, broadcasts." *(open API Reference, then live JSON)*
- "No auth, no signup. It's just there."

---

### Slide 4 — Who It's For + CTA (~15s)

**On screen:** Slide behind you.

```
Built for:
  · journalists tracking committees
  · researchers working with parliamentary data
  · civic tech builders

Live now: <your-domain>
Open source: github.com/harleygray/parliament-search-agent
```

**Talk:**
- "If you're a journalist tracking a committee, a researcher, or anyone building civic tech — go use it."
- "It's live now, it's open source, and the link is in this post."
- *(beat)* "Now — if you care about how it's built, stick around. The architecture is the interesting bit."

---

## PART 2 — TECHNICAL DEEP DIVE (~2 minutes)

The story here: I'm doing **unreliable I/O against a website that's actively trying not to be scraped**, and the BEAM's supervision model makes that a one-line architectural decision instead of a library you bolt on.

---

### Slide 5 — Why Elixir (~25s)

**On screen:** Slide behind you. Simple.

```
Why Elixir / the BEAM

  · scraping is unreliable I/O
  · the scraper WILL fail — WAF blocks, timeouts, garbage HTML
  · I want failures isolated, not cascading
  · supervision trees are a language primitive, not a library
```

**Talk:**
- "First answer: I'm already deep in Elixir on Civic Forum, so zero friction."
- "But the real reason: this is unreliable I/O at scale. I'm hitting a site that might WAF-block me, might time out, might return junk."
- "In most languages you bolt retry and isolation logic on top of async/await. On the BEAM, isolation is the language. The Playwright scraper can crash hard, get restarted, and the API doesn't even notice."

---

### Slide 6 — Architecture (~30s)

**On screen:** Slide behind you — the architecture diagram from the README.

```
┌─────────────────────────────────────────────────────────┐
│                  Phoenix / OTP Application               │
│                                                          │
│  Oban Cron (every 30 min, staggered)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐     │
│  │ReportsScraper│  │HearingScraper│  │BroadcastsSc.│     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘     │
│         ▼                 ▼                  ▼           │
│  ParlinfoClient     ParlinfoClient    ParlViewClient     │
│  (HTTP → Node.js)   (HTTP → Node.js)  (HTTP → APH)       │
│         │                 │                              │
│         ▼                 ▼                              │
│  ┌───────────────────────────────┐                       │
│  │ PlaywrightServer (GenServer)  │                       │
│  │ Elixir Port → node server.js  │                       │
│  │ Chromium (stealth mode)       │                       │
│  └───────────────────────────────┘                       │
│                                                          │
│  Items context (Ecto) → PostgreSQL                       │
│  REST API (9 endpoints)                                  │
│  LiveView dashboard (PubSub real-time updates)           │
└──────────────────────────────────────────────────────────┘
```

**Talk:**
- "Three independent scrape workers, scheduled by Oban, run on a stagger so they're never hitting Playwright at the same time."
- "Each one talks to a tiny Node sidecar that runs the actual headless Chromium. That's the only part that isn't Elixir, and it's deliberately walled off."
- "Underneath: Postgres, a REST API, and a Phoenix LiveView dashboard that pushes updates over PubSub the moment a new row is inserted."

---

### Slide 7 — The Sidecar Trick (~35s)

**On screen:** Open `lib/parliament_search_agent/scraper/playwright_server.ex` in your editor. Highlight `open_port/0` (the `spawn_executable` + `node` line).

Optionally cut to `playwright_server/server.js` showing the `/scrape` endpoint and the WAF detection.

**Talk:**
- "The trickiest bit was lifecycle. I needed Chromium running persistently — spinning up a browser per request is too slow — but I also needed it to die cleanly when the BEAM dies. No orphans."
- "So `PlaywrightServer` is a GenServer that opens a Node process via an Elixir Port using `spawn_executable` — no shell in between. The process tree is literally `BEAM → node`. When the BEAM exits, the port pipe closes, Node sees stdin EOF, Chromium shuts down."
- "On top of that: stealth plugin to dodge fingerprint detection, and a WAF detector that returns a typed `:waf_blocked` error. The worker catches it and snoozes for 10 minutes instead of burning Oban retries." *(this is the supervision-tree payoff — failure is a typed result, not a crash)*

---

### Slide 8 — Oban + Idempotency + LiveView (~30s)

**On screen:** Show `lib/parliament_search_agent/workers/reports_scraper.ex`. Quickly tab to `dashboard_live.ex`'s `handle_info({:new_item, ...})` if there's time.

Then maybe re-open the dashboard and show a "Run now" button or the live feed updating in real time.

**Talk:**
- "Jobs go through Oban, so retries, backoff, and history are stored in Postgres. I get to see exactly what happened and when."
- "ParlInfo returns one search result per *section* of a document, so a 14-chapter report shows up as 14 rows. The upsert collapses them by document ID — every scrape is idempotent. I can re-run a backfill mid-flight and nothing breaks."
- "And when a row gets inserted, the context broadcasts a PubSub event. The LiveView dashboard subscribes at mount and updates the row in place. No polling, no refresh."

---

### Slide 9 — Close (~15s)

**On screen:** Slide behind you.

```
ParlInfo Search Agent

Live:    <your-domain>
Code:    github.com/harleygray/parliament-search-agent
Stack:   Elixir · Phoenix LiveView · Oban · Playwright · Postgres · Fly.io
```

**Talk:**
- "That's the whole thing. It's running on Fly, it's been polling continuously, and the code is open source if you want to read it."
- "If this is useful to you — please use it. If you've got a dataset on ParlInfo I haven't covered yet, raise an issue."
- *(sign off)*

---

## Production notes

- **Total runtime budget:** aim for 2:45–3:15. If you blow past 3:30 the LinkedIn drop-off curve will eat you.
- **First 5 seconds matter most.** Don't open with "hi everyone" — open with the problem statement. The hook is "Australian Parliament has no API."
- **Demo segments need to be live**, not screenshots. The whole credibility move is "this actually works, watch."
- **Editor tip:** when you cut to code (slides 7 & 8), use a big font and a dark theme. People will be watching on phones.
- **Cut the job-application backstory.** It muddies the message. The story is just: I had this problem, I solved it, here it is.
- **One sentence on who it's for** before going technical (covered in Slide 4) — this gives engineers permission to care about the architecture.
