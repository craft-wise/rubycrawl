import "dotenv/config";
import http from "node:http";
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
let contextPromise;

function getBrowser() {
  if (!browserPromise) {
    browserPromise = chromium.launch({ headless: true });
  }
  return browserPromise;
}

async function getContext() {
  if (!contextPromise) {
    const browser = await getBrowser();
    contextPromise = browser.newContext();
  }

  return contextPromise;
}

async function handleCrawl(req, res) {
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
    console.log(`[rubycrawl] crawl start ${body.url}`);

    const context = await getContext();
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
        links: [],
        metadata: {
          status,
          final_url: finalUrl,
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
  }
}

const server = http.createServer((req, res) => {
  // eslint-disable-next-line no-console
  console.log(`[rubycrawl] request ${req.method} ${req.url}`);
  if (req.method === "POST" && req.url === "/crawl") {
    return handleCrawl(req, res);
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
