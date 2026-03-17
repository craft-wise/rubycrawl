# Claude Code Instructions for rubycrawl

## Project Overview

**rubycrawl** is an open-source Ruby gem for crawling websites with full JavaScript rendering, designed for RAG (Retrieval-Augmented Generation) pipelines and general developer use. It uses [Ferrum](https://github.com/rubycdp/ferrum) (pure Ruby Chrome DevTools Protocol client) for browser automation — no Node.js, no external processes.

### Key Characteristics

- **Pure Ruby**: Ferrum drives Chromium directly via CDP — no Node.js dependency
- **RAG-first**: Output is designed for LLM pipelines (`clean_text`, `clean_markdown`, metadata)
- **Developer-friendly**: One-line API that hides browser complexity
- **Rails-native**: ActiveJob patterns, initializer, rake tasks
- **Open source**: MIT licensed, no vendor lock-in

### Who uses this

1. Developers building RAG chatbots who need clean text from any URL
2. Ruby/Rails developers who need a simple, modern web crawler with JS support

---

## Architecture

```
RubyCrawl (lib/rubycrawl.rb)       ← public API
  ↓
Browser (lib/rubycrawl/browser.rb) ← Ferrum wrapper, all browser logic lives here
  ↓
Ferrum::Browser                    ← Chrome DevTools Protocol (pure Ruby)
  ↓
Chromium                           ← headless browser (managed by Ferrum)
```

**Why Ferrum over Node.js/Playwright?**

- Pure Ruby — deploys like any other gem, no npm/Node required
- Same Chrome DevTools Protocol under the hood — identical rendering quality
- One runtime to debug instead of two
- Each `Ferrum::Browser` instance is independent — no shared process/port conflicts

---

## File Structure

```
rubycrawl/
├── lib/
│   ├── rubycrawl.rb                  # Public API, configuration, orchestration
│   └── rubycrawl/
│       ├── version.rb                # Gem version (SemVer)
│       ├── errors.rb                 # Exception hierarchy
│       ├── helpers.rb                # URL validation, payload building, error mapping
│       ├── browser.rb                # Ferrum wrapper — all browser interaction
│       ├── browser/
│       │   ├── extraction.rb         # JS extraction constants (metadata, links, content)
│       │   └── readability.js        # Mozilla Readability.js v0.6.0 (vendored)
│       ├── robots_parser.rb          # robots.txt fetcher and parser
│       ├── url_normalizer.rb         # URL normalization, deduplication, tracking param removal
│       ├── markdown_converter.rb     # HTML → Markdown (reverse_markdown, lazy)
│       ├── result.rb                 # Result object with lazy clean_markdown
│       ├── site_crawler.rb           # BFS multi-page crawler with depth limits
│       ├── railtie.rb                # Rails integration
│       └── tasks/
│           └── install.rake          # `rake rubycrawl:install`
├── spec/
│   ├── rubycrawl_spec.rb             # Unit + integration tests
│   ├── browser_integration_spec.rb   # Browser integration tests (data: URLs, no network)
│   ├── url_normalizer_spec.rb        # UrlNormalizer unit tests
│   ├── site_crawler_spec.rb          # SiteCrawler unit tests
│   └── spec_helper.rb
├── .github/
│   ├── workflows/
│   │   └── ci.yml                    # GitHub Actions CI (RuboCop + RSpec)
│   └── copilot-instructions.md
├── CLAUDE.md                         # This file
├── README.md                         # User-facing documentation
├── rubycrawl.gemspec
└── Rakefile
```

---

## Understanding the Codebase

### Public API (`lib/rubycrawl.rb`)

```ruby
RubyCrawl.crawl(url, **options)                  # → Result
RubyCrawl.crawl_site(url, **options) { |page| }  # → Integer (pages crawled)
RubyCrawl.configure(**defaults)
```

Configuration options:

- `wait_until` — `"load"`, `"networkidle"`, `"domcontentloaded"` (default: nil = Ferrum default)
- `block_resources` — true/false (blocks images/fonts/CSS, default: nil)
- `max_attempts` — retry count (default: 3)
- `timeout` — browser timeout in seconds (default: 30)
- `respect_robots_txt` — honour robots.txt Disallow rules and Crawl-delay (default: false)

### Browser (`lib/rubycrawl/browser.rb`)

The core of the gem. Wraps Ferrum and owns all browser interaction:

- Launches a single `Ferrum::Browser` instance (singleton, lazy)
- Creates isolated page contexts per crawl (or reuses session contexts)
- Runs JS extraction via `page.evaluate()` — metadata, links, raw text, clean content
- Handles resource blocking via `page.network.intercept`
- Maps Ferrum exceptions to rubycrawl's error hierarchy

**Content extraction JS constants** live in `lib/rubycrawl/browser/extraction.rb`:

- `EXTRACT_METADATA_JS` — OG tags, Twitter cards, title, description, canonical, lang
- `EXTRACT_LINKS_JS` — all `a[href]` with url/text/title/rel
- `EXTRACT_RAW_TEXT_JS` — `body.innerText` as unfiltered plain text
- `EXTRACT_CONTENT_JS` — content extraction: Mozilla Readability.js (primary, article pages) with link-density heuristic fallback (nav-heavy/sparse pages). Returns `{ cleanHtml, extractor }` where `extractor` is `"readability"` or `"heuristic"`. Readability.js source is embedded inside the same IIFE so both share the same `Runtime.evaluate` scope.

All constants are IIFEs (`(() => { ... })()`) — required because `Ferrum#page.evaluate` evaluates an expression, not a function definition.

### Result (`lib/rubycrawl/result.rb`)

Immutable value object returned from every crawl:

- `result.html` — full raw HTML
- `result.raw_text` — unfiltered `body.innerText`
- `result.clean_text` — noise-stripped plain text (ready for RAG chunking)
- `result.clean_html` — noise-stripped HTML
- `result.clean_markdown` — lazy: computed from `clean_html` on first access
- `result.links` — array of `{ 'url', 'text', 'title', 'rel' }` hashes
- `result.metadata` — status, final*url, og*\_, twitter\_\_, canonical, lang, charset
- `result.final_url` — shortcut for `metadata['final_url']`

### SiteCrawler (`lib/rubycrawl/site_crawler.rb`)

BFS multi-page crawler:

- Takes a `RubyCrawl` client instance and options
- Yields `SiteCrawler::PageResult` (same interface as `Result` + `depth` attribute)
- Each page gets its own isolated browser context via `Browser#crawl`
- Deduplicates via `Set` of normalized URLs
- Handles redirects: marks `final_url` as visited
- Silently skips failed pages (logs warning), continues crawling
- `respect_robots_txt: true` fetches robots.txt once, skips disallowed URLs, auto-sleeps `Crawl-delay`

### RobotsParser (`lib/rubycrawl/robots_parser.rb`)

Fetches and parses `robots.txt` for a site:

- `RobotsParser.fetch(base_url)` — downloads via `Net::HTTP`, 5s timeout, fails open on error
- `allowed?(url)` — checks `User-agent: *` Disallow/Allow rules; Allow takes precedence
- `crawl_delay` — returns `Crawl-delay` value as Float, or nil
- Supports `*` wildcard and `$` end-of-string anchor in rule patterns

### UrlNormalizer (`lib/rubycrawl/url_normalizer.rb`)

- Lowercases scheme/host, removes fragments, removes trailing slashes
- Strips tracking params: `utm_*`, `fbclid`, `gclid`
- Sorts query params for canonical form
- Resolves relative URLs against a base URL
- `same_host?` treats www and non-www as the same host

---

## Making Changes

### Adding a new extraction field

1. Add the JS to the relevant constant in `browser.rb`:

   ```ruby
   EXTRACT_METADATA_JS = <<~JS
     (() => {
       // add new field here
       return { ..., newField: document.querySelector('...') };
     })()
   JS
   ```

2. Map it in `Browser#extract` in `browser.rb`

3. Add `attr_reader` to `Result` and `SiteCrawler::PageResult`

4. Update `Result#initialize`

5. Add tests and update README

### Adding a new configuration option

1. Add keyword arg to `RubyCrawl#crawl` and `RubyCrawl#load_options`
2. Pass it through to `Browser` in the options hash
3. Handle it in `Browser#crawl`
4. Document in README

---

## Testing

- **Unit tests** (`rubycrawl_spec.rb`, `url_normalizer_spec.rb`, `site_crawler_spec.rb`) — mock the browser, fast, no Chrome needed
- **Browser integration tests** (`browser_integration_spec.rb`) — real Chrome, use `data:` URLs (no network, works offline and on CI)
- All tests run together — no flags needed

```bash
bundle exec rspec          # runs all tests (unit + browser integration)
bundle exec rubocop        # lint
```

---

## Error Hierarchy

```
StandardError
  └── RubyCrawl::Error
        ├── ServiceError      — browser failed to start or crashed
        ├── NavigationError   — page navigation failed (bad URL, timeout, HTTP error)
        ├── TimeoutError      — page load timed out
        └── ConfigurationError — invalid URL or option value
```

Map Ferrum exceptions in `browser.rb`:

- `Ferrum::TimeoutError` → `RubyCrawl::TimeoutError`
- `Ferrum::StatusError` → `RubyCrawl::NavigationError`
- `Ferrum::NodeNotFoundError` → `RubyCrawl::NavigationError`
- `Ferrum::Error` (base) → `RubyCrawl::ServiceError`

---

## Design Philosophy

1. **RAG-first output**: `clean_text` and `clean_markdown` are the primary outputs — optimised for LLM consumption, not raw HTML
2. **Correctness over speed**: A slow but correct crawl beats a fast but wrong one
3. **Hide browser complexity**: Users should never need to know Ferrum exists
4. **Pure Ruby**: No external runtime dependencies beyond Chrome (managed by Ferrum)
5. **Simplicity over cleverness**: Boring, readable code

### What belongs in this gem

- Crawling public websites and extracting clean content
- BFS multi-page crawling with deduplication
- RAG-ready output (clean text, markdown, metadata)
- Rails integration (ActiveJob patterns, initializer)

### What does NOT belong in this gem

- Interactive browser automation (clicking, scrolling, form filling) — use Ferrum directly
- Screenshot capture / PDF generation — use Ferrum directly
- Authenticated crawling (OAuth flows) — out of scope
- JavaScript execution on behalf of users — out of scope

---

## Code Review Checklist

- [ ] Public API is clean and Ruby-idiomatic?
- [ ] Ferrum complexity is hidden from users?
- [ ] All browser resources cleaned up (pages closed in ensure blocks)?
- [ ] Ferrum exceptions mapped to rubycrawl error hierarchy?
- [ ] Changes backward compatible (or version bump justified)?
- [ ] README updated if API changed?
- [ ] Tests cover new behaviour including error paths?

---

## Quick Reference

```bash
# Setup
bin/setup

# Run all tests
bundle exec rspec

# Install Chrome for Ferrum
bundle exec rake rubycrawl:install

# Manual testing
bin/console
> RubyCrawl.crawl("https://example.com")
> RubyCrawl.crawl("https://example.com").clean_text
> RubyCrawl.crawl("https://example.com").clean_markdown
```

---

## Reference

- [Ferrum docs](https://github.com/rubycdp/ferrum)
- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
- [Ruby style guide](https://rubystyle.guide/)
- [SemVer](https://semver.org/)
