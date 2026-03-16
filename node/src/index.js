import "dotenv/config";
import http from "node:http";
import crypto from "node:crypto";
import { chromium } from "playwright";

const HOST = "127.0.0.1";
const PORT = process.env.RUBYCRAWL_NODE_PORT || 3344;
const DEFAULT_BLOCK_RESOURCES = true;
const BLOCKED_RESOURCE_TYPES = new Set([
  "image",
  "media",
  "font",
  "stylesheet",
]);

function json(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

const MAX_BODY_SIZE = 1 * 1024 * 1024; // 1 MB

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_SIZE) {
        reject(new Error("Request body too large"));
        req.destroy();
        return;
      }
      data += chunk;
    });
    req.on("end", () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function validateRequest(body) {
  if (!body || typeof body.url !== "string" || body.url.trim() === "") {
    return { ok: false, error: "url is required" };
  }
  return { ok: true };
}

let browser = null;

// Session storage: session_id -> { context, createdAt, lastUsedAt }
const sessions = new Map();

// Session TTL: 30 minutes of inactivity
const SESSION_TTL_MS = 30 * 60 * 1000;
// Cleanup interval: every 5 minutes
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

function generateSessionId() {
  return `sess_${crypto.randomBytes(16).toString("hex")}`;
}

async function getBrowser() {
  if (browser && browser.isConnected()) return browser;
  browser = await chromium.launch({ headless: true });
  return browser;
}

/**
 * Create a fresh browser context.
 */
async function createContext() {
  const browser = await getBrowser();
  return browser.newContext();
}

/**
 * Get or create context based on session_id.
 * If session_id provided and exists, reuse existing context.
 * If session_id provided but expired/destroyed, create new context (handles retries).
 * Otherwise create a fresh one-off context.
 */
async function getContext(sessionId) {
  if (sessionId && sessions.has(sessionId)) {
    // Update last used time
    const session = sessions.get(sessionId);
    session.lastUsedAt = Date.now();
    return { context: session.context, isSession: true };
  }

  // If session_id provided but doesn't exist (expired/destroyed), recreate it
  // This handles job retries gracefully
  if (sessionId) {
    const context = await createContext();
    const now = Date.now();
    sessions.set(sessionId, { context, createdAt: now, lastUsedAt: now });
    // eslint-disable-next-line no-console
    console.log(
      `[rubycrawl] session recreated ${sessionId} (was expired or destroyed)`,
    );
    return { context, isSession: true };
  }

  return { context: await createContext(), isSession: false };
}

/**
 * Cleanup expired sessions (no activity for SESSION_TTL_MS).
 */
async function cleanupExpiredSessions() {
  const now = Date.now();
  const expiredIds = [];

  for (const [sessionId, session] of sessions) {
    if (now - session.lastUsedAt > SESSION_TTL_MS) {
      expiredIds.push(sessionId);
    }
  }

  for (const sessionId of expiredIds) {
    const session = sessions.get(sessionId);
    await session.context.close().catch(() => {});
    sessions.delete(sessionId);
    // eslint-disable-next-line no-console
    console.log(
      `[rubycrawl] session expired ${sessionId} (inactive for ${SESSION_TTL_MS / 60000} min)`,
    );
  }

  if (expiredIds.length > 0) {
    // eslint-disable-next-line no-console
    console.log(
      `[rubycrawl] cleanup: ${expiredIds.length} expired, ${sessions.size} active`,
    );
  }
}

// Start cleanup interval
setInterval(cleanupExpiredSessions, CLEANUP_INTERVAL_MS);

/**
 * Extract HTML metadata from the page
 */
async function extractMetadata(page) {
  return page.evaluate(() => {
    const getMeta = (name) => {
      const meta = document.querySelector(
        `meta[name="${name}"], meta[property="${name}"]`,
      );
      return meta?.getAttribute("content") || null;
    };

    const getLink = (rel) => {
      const link = document.querySelector(`link[rel="${rel}"]`);
      return link?.getAttribute("href") || null;
    };

    return {
      title: document.title || null,
      description: getMeta("description") || getMeta("og:description") || null,
      keywords: getMeta("keywords"),
      author: getMeta("author"),
      og_title: getMeta("og:title"),
      og_description: getMeta("og:description"),
      og_image: getMeta("og:image"),
      og_url: getMeta("og:url"),
      og_type: getMeta("og:type"),
      twitter_card: getMeta("twitter:card"),
      twitter_title: getMeta("twitter:title"),
      twitter_description: getMeta("twitter:description"),
      twitter_image: getMeta("twitter:image"),
      canonical: getLink("canonical"),
      lang: document.documentElement.lang || null,
      charset: document.characterSet || null,
    };
  });
}

/**
 * Extract links from the page.
 */
async function extractLinks(page) {
  return page.evaluate(() => {
    const links = Array.from(document.querySelectorAll("a[href]"));
    return links.map((link) => ({
      url: link.href,
      text: (link.textContent || "").trim(),
      title: link.getAttribute("title") || null,
      rel: link.getAttribute("rel") || null,
    }));
  });
}

/**
 * Extract raw plain text from the page using body.innerText (unfiltered).
 */
async function extractRawText(page) {
  return page.evaluate(() => (document.body?.innerText || "").trim());
}

// Semantic noise selectors — no class names, works across all sites.
// Covers standard HTML5 elements and ARIA roles that browsers/frameworks emit.
const NOISE_SELECTORS = [
  "nav",
  "header",
  "footer",
  "aside",
  '[role="navigation"]',
  '[role="banner"]',
  '[role="contentinfo"]',
  '[role="complementary"]',
  '[role="dialog"]',
  '[role="tooltip"]',
  '[role="alert"]',
  '[aria-hidden="true"]',
  "script",
  "style",
  "noscript",
  "iframe",
].join(", ");


/**
 * Extract clean content text by removing noise containers and returning
 * everything that remains.
 *
 * Strategy:
 *   1. Remove semantic noise elements (nav/header/footer/aside + ARIA roles +
 *      script/style/noscript/iframe) from a working copy of the body.
 *   2. Use link density to also remove non-semantic noise containers
 *      (e.g. <div class="footer-area"> that should be <footer> but isn't).
 *   3. Return innerText of what remains, preserving paragraph breaks.
 *
 * This approach works well for business websites (landing pages, pricing,
 * FAQ, feature pages) where content is spread across many <section> elements
 * rather than concentrated in a single <main> or <article>.
 */
async function extractContent(page) {
  return page.evaluate(({ noiseSelectors }) => {
    // Link-density heuristic: identifies containers that are mostly links.
    function linkDensity(el) {
      const total = (el.innerText || "").trim().length;
      if (!total) return 1;
      const linked = Array.from(el.querySelectorAll("a")).reduce(
        (sum, a) => sum + (a.innerText || "").trim().length,
        0,
      );
      return linked / total;
    }

    // Collect all noise elements to remove temporarily.
    // We mutate the live DOM so innerText gets proper CSS-computed line breaks,
    // then restore everything afterwards.
    const removed = [];
    function stash(el) {
      if (el.parentNode) {
        removed.push({ el, parent: el.parentNode, next: el.nextSibling });
        el.parentNode.removeChild(el);
      }
    }

    // 1. Remove semantic noise elements.
    document.body.querySelectorAll(noiseSelectors).forEach(stash);

    // 2. Remove high link-density top-level containers (non-semantic footers/navs).
    const blockTags = new Set(["script","style","noscript","link","meta"]);
    const topChildren = Array.from(document.body.children).filter(
      (el) => !blockTags.has(el.tagName.toLowerCase()),
    );
    const roots =
      topChildren.length === 1 ? [document.body, topChildren[0]] : [document.body];

    for (const root of roots) {
      for (const el of Array.from(root.children)) {
        const text = (el.innerText || "").trim();
        if (text.length >= 20 && linkDensity(el) > 0.5) stash(el);
      }
    }

    // 3. Read innerText and innerHTML with noise removed (CSS layout still applies → proper newlines).
    const cleanText = (document.body.innerText || "")
      .trim()
      .replace(/\n{3,}/g, "\n\n")
      .replace(/[ \t]{2,}/g, " ");

    const cleanHtml = document.body.innerHTML;

    // 4. Restore removed elements so the page is unchanged.
    removed.reverse().forEach(({ el, parent, next }) => parent.insertBefore(el, next));

    return { cleanText, cleanHtml };
  }, { noiseSelectors: NOISE_SELECTORS });
}

async function handleCrawl(req, res) {
  let context = null;
  let isSession = false;

  try {
    const body = await readJson(req);
    const validation = validateRequest(body);
    if (!validation.ok) {
      return json(res, 422, { error: validation.error });
    }

    const waitUntil = body.wait_until || "load";
    const blockResources =
      typeof body.block_resources === "boolean"
        ? body.block_resources
        : DEFAULT_BLOCK_RESOURCES;

    const start = Date.now();
    // eslint-disable-next-line no-console
    console.log(
      `[rubycrawl] crawl start ${body.url}${body.session_id ? ` (session=${body.session_id})` : ""}`,
    );

    // Get context (reuse if session_id provided)
    const ctxResult = await getContext(body.session_id);
    context = ctxResult.context;
    isSession = ctxResult.isSession;

    const page = await context.newPage();

    try {
      if (blockResources) {
        await page.route("**/*", (route) => {
          const type = route.request().resourceType();
          if (BLOCKED_RESOURCE_TYPES.has(type)) {
            return route.abort();
          }
          return route.continue();
        });
      }

      const response = await page.goto(body.url, {
        waitUntil,
        timeout: 30_000,
      });

      const html = await page.content();
      const finalUrl = page.url();
      const status = response ? response.status() : null;
      const htmlMetadata = await extractMetadata(page);
      const links = await extractLinks(page);
      const rawText = await extractRawText(page);
      const { cleanText, cleanHtml } = await extractContent(page);

      // eslint-disable-next-line no-console
      console.log(
        `[rubycrawl] crawl done ${body.url} status=${status} ms=${Date.now() - start}`,
      );

      return json(res, 200, {
        ok: true,
        url: body.url,
        html,
        raw_text: rawText,
        clean_text: cleanText,
        clean_html: cleanHtml,
        links,
        metadata: {
          status,
          final_url: finalUrl,
          ...htmlMetadata,
        },
      });
    } finally {
      await page.close();
    }
  } catch (error) {
    const code =
      error?.name === "SyntaxError" ? "invalid_json" : "crawl_failed";
    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] crawl error ${code} ${error?.message || ""}`);
    return json(res, 400, { error: code, message: error?.message });
  } finally {
    // Only close context if not a session (sessions are managed separately)
    if (context && !isSession) {
      await context.close().catch(() => {});
    }
  }
}

/**
 * Create a new session with a reusable browser context.
 */
async function handleSessionCreate(req, res) {
  try {
    const sessionId = generateSessionId();
    const context = await createContext();
    const now = Date.now();
    sessions.set(sessionId, { context, createdAt: now, lastUsedAt: now });

    // eslint-disable-next-line no-console
    console.log(
      `[rubycrawl] session created ${sessionId} (active=${sessions.size})`,
    );

    return json(res, 200, { ok: true, session_id: sessionId });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] session create error ${error?.message || ""}`);
    return json(res, 400, {
      error: "session_create_failed",
      message: error?.message,
    });
  }
}

/**
 * Destroy a session and close its browser context.
 * Returns success even if session doesn't exist (idempotent for retries).
 */
async function handleSessionDestroy(req, res) {
  try {
    const body = await readJson(req);
    const sessionId = body.session_id;

    if (!sessionId) {
      return json(res, 422, { error: "session_id required" });
    }

    // Idempotent: if session doesn't exist, still return success
    if (!sessions.has(sessionId)) {
      return json(res, 200, {
        ok: true,
        message: "session already destroyed or expired",
      });
    }

    const session = sessions.get(sessionId);
    await session.context.close().catch(() => {});
    sessions.delete(sessionId);

    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] session destroyed ${sessionId}`);

    return json(res, 200, { ok: true });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] session destroy error ${error?.message || ""}`);
    return json(res, 400, {
      error: "session_destroy_failed",
      message: error?.message,
    });
  }
}

const server = http.createServer((req, res) => {
  // eslint-disable-next-line no-console
  console.log(`[rubycrawl] request ${req.method} ${req.url}`);

  if (req.method === "POST" && req.url === "/crawl") {
    return handleCrawl(req, res);
  }

  if (req.method === "POST" && req.url === "/session/create") {
    return handleSessionCreate(req, res);
  }

  if (req.method === "POST" && req.url === "/session/destroy") {
    return handleSessionDestroy(req, res);
  }

  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, { ok: true });
  }

  return json(res, 404, { error: "not_found" });
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`rubycrawl node service listening on http://${HOST}:${PORT}`);
});
