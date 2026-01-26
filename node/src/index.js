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

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
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

let browserPromise;

// Session storage: session_id -> { context, createdAt, lastUsedAt }
const sessions = new Map();

// Session TTL: 30 minutes of inactivity
const SESSION_TTL_MS = 30 * 60 * 1000;
// Cleanup interval: every 5 minutes
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

function generateSessionId() {
  return `sess_${crypto.randomBytes(16).toString("hex")}`;
}

function getBrowser() {
  if (!browserPromise) {
    browserPromise = chromium.launch({ headless: true });
  }
  return browserPromise;
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
    console.log(`[rubycrawl] session recreated ${sessionId} (was expired or destroyed)`);
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
    console.log(`[rubycrawl] session expired ${sessionId} (inactive for ${SESSION_TTL_MS / 60000} min)`);
  }

  if (expiredIds.length > 0) {
    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] cleanup: ${expiredIds.length} expired, ${sessions.size} active`);
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
    console.log(`[rubycrawl] crawl start ${body.url}${body.session_id ? ` (session=${body.session_id})` : ""}`);

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

      // eslint-disable-next-line no-console
      console.log(
        `[rubycrawl] crawl done ${body.url} status=${status} ms=${Date.now() - start}`,
      );

      return json(res, 200, {
        ok: true,
        url: body.url,
        html,
        text: "",
        markdown: "",
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
    console.log(`[rubycrawl] session created ${sessionId} (active=${sessions.size})`);

    return json(res, 200, { ok: true, session_id: sessionId });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.log(`[rubycrawl] session create error ${error?.message || ""}`);
    return json(res, 400, { error: "session_create_failed", message: error?.message });
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
      return json(res, 200, { ok: true, message: "session already destroyed or expired" });
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
    return json(res, 400, { error: "session_destroy_failed", message: error?.message });
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
