"use strict";

const fs = require("fs");
const path = require("path");
const express = require("express");
const { chromium } = require("playwright-extra");
const StealthPlugin = require("puppeteer-extra-plugin-stealth");

const DIAG_DIR = path.join(__dirname, "..", "priv", "diagnostics");
const DIAGNOSTICS_ENABLED = false;

chromium.use(StealthPlugin());

const PORT = process.env.PLAYWRIGHT_PORT || 4003;
const app = express();
app.use(express.json());

let browser = null;
let server = null;
let shutdownInProgress = false;

// Register stdin EOF listener at top level so BEAM death is caught even during startup.
// When the Elixir port pipe closes (for any reason), node exits cleanly.
process.stdin.resume();
process.stdin.on("end", () => shutdown().catch(() => process.exit(0)));

async function getBrowser() {
  if (!browser) {
    browser = await chromium.launch({
      headless: true,
      executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
      ],
    });
  }
  return browser;
}

async function shutdown() {
  if (shutdownInProgress) return;
  shutdownInProgress = true;

  console.log("Shutting down playwright server...");
  if (server) server.close();
  if (browser) {
    await Promise.race([
      browser.close(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("browser.close() timed out")), 3000)
      ),
    ]).catch(() => {});
  }
  process.exit(0);
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/scrape", async (req, res) => {
  const { url } = req.body;

  if (!url) {
    return res.status(400).json({ error: "url is required" });
  }

  const startTime = Date.now();
  let context = null;

  console.log("scrape:start url=" + url);

  try {
    const b = await getBrowser();
    context = await b.newContext({
      userAgent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    });

    const page = await context.newPage();

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    const pageTitle = await page.title();
    const finalUrl = page.url();
    console.log("scrape:navigated title=" + JSON.stringify(pageTitle) + " final_url=" + finalUrl);

    if (pageTitle.includes("WAF Block") || pageTitle.includes("Web Application Firewall")) {
      console.warn("scrape:waf_blocked url=" + url);
      await context.close().catch(() => {});
      context = null;
      return res.status(403).json({ error: "waf_blocked", url });
    }

    console.log("scrape:selector_wait");
    await page.waitForSelector("li.result, .result-row, .search-result, table.searchresults tr, div[class*='result']", {
      timeout: 15000,
    }).then(async (el) => {
      const elDesc = await el.evaluate((n) => n.tagName + (n.id ? "#" + n.id : "") + (n.className ? "." + String(n.className).trim().split(/\s+/).join(".") : ""));
      console.log("scrape:selector_found element=" + elDesc);
    }).catch(() => {
      console.log("scrape:selector_missing");
    });

    const { items, rowErrors, diag } = await page.evaluate((diagEnabled) => {
      const results = [];
      const errors = [];

      // ParlInfo search results: <ul id="results"><li class="result hiliteRow|loliteRow">
      const rows = document.querySelectorAll("li.result");

      const allLinks = diagEnabled
        ? Array.from(document.querySelectorAll("a[href]")).map((a) => ({
            href: a.href,
            text: (a.textContent || "").trim().slice(0, 100),
            parentTag: a.parentElement
              ? a.parentElement.tagName +
                (a.parentElement.className
                  ? "." + String(a.parentElement.className).trim().split(/\s+/).join(".")
                  : "")
              : null,
          }))
        : [];

      const container = diagEnabled ? document.querySelector(".resultsMainCol") : null;
      const containerHtml = container ? container.innerHTML.slice(0, 20000) : null;
      const containerChildren = container
        ? Array.from(container.children).slice(0, 20).map((el) => ({
            tag: el.tagName,
            id: el.id || null,
            classes: el.className || null,
            childCount: el.children.length,
            textSnippet: (el.textContent || "").trim().slice(0, 80),
          }))
        : [];

      rows.forEach((row) => {
        try {
          const linkEl = row.querySelector("div.sumLink a");
          if (!linkEl) return;

          const checkboxEl = row.querySelector("input[name='title']");
          const parlinfo_id = checkboxEl ? checkboxEl.value : null;
          if (!parlinfo_id) return;

          const sourceUrl = linkEl.href;
          const title = (linkEl.textContent || "").trim();

          const metaEl = row.querySelector(".sumMeta");
          const metaText = metaEl ? (metaEl.textContent || "").trim() : "";
          // Reformat DD/MM/YYYY -> YYYY-MM-DD for Ecto :date cast
          const dateMatch = metaText.match(/Date:\s*(\d{2})\/(\d{2})\/(\d{4})/);
          const date_tabled = dateMatch ? `${dateMatch[3]}-${dateMatch[2]}-${dateMatch[1]}` : null;

          results.push({
            parlinfo_id,
            title,
            date_tabled,
            committee_name: null,
            chamber: null,
            pdf_url: null,
            source_url: sourceUrl,
          });
        } catch (e) {
          errors.push(e.message);
        }
      });

      return {
        items: results,
        rowErrors: errors,
        diag: { rowCount: rows.length, allLinks, containerHtml, containerChildren },
      };
    }, DIAGNOSTICS_ENABLED);

    rowErrors.forEach((msg) => console.error("scrape:row_error " + msg));
    console.log("scrape:diag rows_matched=" + diag.rowCount);

    if (DIAGNOSTICS_ENABLED && diag.rowCount === 0) {
      // Write full diagnostic snapshot so we can determine the real selectors.
      const slug = url.replace(/[^a-zA-Z0-9]/g, "_").slice(0, 80);
      const ts = new Date().toISOString().replace(/[:.]/g, "-");
      const diagFile = path.join(DIAG_DIR, ts + "__" + slug + ".json");
      const diagPayload = {
        scraped_at: new Date().toISOString(),
        url,
        page_title: pageTitle,
        final_url: finalUrl,
        all_links: diag.allLinks,
        container_children: diag.containerChildren,
        container_html: diag.containerHtml,
      };
      try {
        fs.mkdirSync(DIAG_DIR, { recursive: true });
        fs.writeFileSync(diagFile, JSON.stringify(diagPayload, null, 2), "utf8");
        console.log("scrape:diag_saved path=" + diagFile);
      } catch (writeErr) {
        console.error("scrape:diag_write_error " + writeErr.message);
      }
    }

    console.log("scrape:extracted count=" + items.length);
    console.log("scrape:done count=" + items.length + " duration_ms=" + (Date.now() - startTime));

    res.json({ items });
  } catch (err) {
    console.error("Scrape error:", err.message);
    res.status(500).json({ error: err.message });
  } finally {
    if (context) {
      await context.close().catch(() => {});
    }
  }
});

const ITEM_DIAG_DIR = path.join(DIAG_DIR, "items");

app.post("/scrape_item", async (req, res) => {
  const { url, dataset } = req.body;

  if (!url || !dataset) {
    return res.status(400).json({ error: "url and dataset are required" });
  }

  const startTime = Date.now();
  let context = null;

  console.log("scrape_item:start dataset=" + dataset + " url=" + url);

  try {
    const b = await getBrowser();
    context = await b.newContext({
      userAgent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    });

    const page = await context.newPage();

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    const pageTitle = await page.title();
    const finalUrl = page.url();
    console.log("scrape_item:navigated title=" + JSON.stringify(pageTitle));

    if (pageTitle.includes("WAF Block") || pageTitle.includes("Web Application Firewall")) {
      console.warn("scrape_item:waf_blocked url=" + url);
      await context.close().catch(() => {});
      context = null;
      return res.status(403).json({ error: "waf_blocked", url });
    }

    const { fields, allLinks, pageHtml, parlinfo_id } = await page.evaluate(() => {
      // PDF links — "Download PDF" link is most reliable
      const pdfLinks = Array.from(document.querySelectorAll("a[href]"))
        .map((a) => a.href)
        .filter((href) => /\.pdf(\?|;|$)/i.test(href) || href.includes("fileType=application%2Fpdf"));

      const pdf_url = pdfLinks.length > 0 ? pdfLinks[0] : null;

      // ParlInfo metadata: dt.mdLabel / dd.mdValue p.mdItem pairs
      // These exist in both the visible .metadata div and the hidden #metadataExtra div —
      // both are in the DOM and readable even when CSS-hidden.
      const getMeta = (label) => {
        const dts = document.querySelectorAll("dt.mdLabel");
        for (const dt of dts) {
          if ((dt.textContent || "").trim() === label) {
            const dd = dt.nextElementSibling;
            if (!dd) continue;
            const items = Array.from(dd.querySelectorAll("p.mdItem"))
              .map((p) => (p.textContent || "").trim())
              .filter((t) => t && t !== " ");
            return items.length > 0 ? items[0] : null;
          }
        }
        return null;
      };

      // Convert "DD/MM/YYYY" (and optional time) to "YYYY-MM-DDTHH:MM:SS"
      const parseDate = (raw) => {
        if (!raw) return null;
        const m = raw.match(/(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}:\d{2}:\d{2}))?/);
        if (!m) return null;
        const time = m[4] || "00:00:00";
        return `${m[3]}-${m[2]}-${m[1]}T${time}`;
      };

      // Convert "DD-MM-YYYY HH:MM AM/PM" (broadcast format) to "YYYY-MM-DDTHH:MM:SS"
      const parseBroadcastDateTime = (raw) => {
        if (!raw) return null;
        const m = raw.match(/(\d{2})-(\d{2})-(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)/i);
        if (!m) return null;
        let hours = parseInt(m[4], 10);
        const minutes = m[5];
        const ampm = m[6].toUpperCase();
        if (ampm === "PM" && hours !== 12) hours += 12;
        if (ampm === "AM" && hours === 12) hours = 0;
        return `${m[3]}-${m[2]}-${m[1]}T${String(hours).padStart(2, "0")}:${minutes}:00`;
      };

      // Get the href of the anchor inside a metadata dd (for fields like "URL")
      const getMetaHref = (label) => {
        const dts = document.querySelectorAll("dt.mdLabel");
        for (const dt of dts) {
          if ((dt.textContent || "").trim() === label) {
            const dd = dt.nextElementSibling;
            if (!dd) continue;
            const link = dd.querySelector("a[href]");
            return link ? link.href : null;
          }
        }
        return null;
      };

      // "Committee Name" or "Committee" depending on the dataset
      const committee_name = getMeta("Committee Name") || getMeta("Committee");
      // "Source" holds the chamber: "Joint", "Senate", "House of Representatives", etc.
      const chamber = getMeta("Source");
      const parl_no_raw = getMeta("Parl No.");
      const parliament_number = parl_no_raw ? parseInt(parl_no_raw, 10) || null : null;
      const date_referred = parseBroadcastDateTime(getMeta("Referred Date") || getMeta("Date Referred") || getMeta("Referred"));
      const inquiry_name = getMeta("Inquiry Name") || getMeta("Inquiry");
      const report_type = getMeta("Report Type");

      // Permalink contains the canonical parlinfo_id
      const permalinkEl = document.querySelector("a.permalink");
      const permalinkHref = permalinkEl ? permalinkEl.href : null;
      // Extract id from e.g. ...;query=Id%3A%22committees%2Fcommjnt%2F29475%2F0007%22
      let parlinfo_id = null;
      if (permalinkHref) {
        const m = permalinkHref.match(/[?;]query=Id%3A%22([^"]+)%22/);
        if (m) parlinfo_id = decodeURIComponent(m[1]);
      }

      const parlview_url = getMetaHref("URL");
      const start_time = parseBroadcastDateTime(getMeta("Start"));
      const end_time = parseBroadcastDateTime(getMeta("End"));
      const duration = getMeta("Duration");

      const fields = {
        pdf_url,
        committee_name,
        chamber,
        parliament_number,
        date_referred,
        inquiry_name,
        report_type,
        parlview_url,
        start_time,
        end_time,
        duration,
      };

      // Diagnostic data
      const allLinks = Array.from(document.querySelectorAll("a[href]")).map((a) => ({
        href: a.href,
        text: (a.textContent || "").trim().slice(0, 100),
      }));

      const pageHtml = document.documentElement.innerHTML.slice(0, 30000);

      return { fields, allLinks, pageHtml, parlinfo_id };
    });

    // Use parlinfo_id as the diagnostic filename so each item gets its own file,
    // even when multiple items share a long search-result URL prefix.
    const diagSlug = parlinfo_id
      ? parlinfo_id.replace(/[^a-zA-Z0-9]/g, "_")
      : url.replace(/[^a-zA-Z0-9]/g, "_").slice(0, 120);
    const diagFile = path.join(ITEM_DIAG_DIR, diagSlug + ".json");
    const diagPayload = {
      scraped_at: new Date().toISOString(),
      url,
      dataset,
      page_title: pageTitle,
      final_url: finalUrl,
      extracted_fields: fields,
      all_links: allLinks,
      page_html: pageHtml,
    };
    if (DIAGNOSTICS_ENABLED) {
      try {
        fs.mkdirSync(ITEM_DIAG_DIR, { recursive: true });
        fs.writeFileSync(diagFile, JSON.stringify(diagPayload, null, 2), "utf8");
        console.log("scrape_item:diag_saved path=" + diagFile);
      } catch (writeErr) {
        console.error("scrape_item:diag_write_error " + writeErr.message);
      }
    }

    console.log(
      "scrape_item:done dataset=" + dataset + " duration_ms=" + (Date.now() - startTime)
    );

    res.json({ fields });
  } catch (err) {
    console.error("scrape_item error:", err.message);
    res.status(500).json({ error: err.message });
  } finally {
    if (context) {
      await context.close().catch(() => {});
    }
  }
});

async function main() {
  await getBrowser();
  console.log("Chromium browser initialized");

  server = app.listen(PORT, () => {
    console.log(`Playwright server listening on port ${PORT}`);
  });

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("Fatal startup error:", err);
  process.exit(1);
});
