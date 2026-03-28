# Changelog

All notable changes to rubycrawl are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.1] - 2026-03-28

### Fixed
- Chrome now launches correctly in Docker and Linux environments without manual configuration. `--no-sandbox` and `--disable-dev-shm-usage` flags are applied by default (safe on all platforms, required in Docker).

---

## [0.4.0] - 2026-03-17

### Added
- **`respect_robots_txt` option** — opt-in robots.txt compliance for `crawl_site` and `RubyCrawl.configure` (default: `false`). When enabled:
  - Fetches `robots.txt` once at the start of each site crawl
  - Skips URLs disallowed for `User-agent: *` (logs a warning per skipped URL)
  - Automatically sleeps `Crawl-delay` seconds between pages when the site specifies it
  - Fails open — if robots.txt is unreachable or missing, crawling proceeds normally
- **`RobotsParser`** — built-in robots.txt parser with no extra gem dependency. Supports `Disallow`, `Allow` (takes precedence over Disallow), `Crawl-delay`, `*` wildcard, and `$` end-of-string anchor patterns.
- **GitHub Actions CI** — RuboCop + RSpec matrix on Ruby 3.3 with Chrome installed via `browser-actions/setup-chrome`.
- **100-test suite** — up from 77 tests, adding 18 new tests in `spec/robots_parser_spec.rb` and `spec/site_crawler_spec.rb`.

### Changed
- Rails initializer template now includes `respect_robots_txt` as a commented-out option.

---

## [0.3.0] - 2026-03-17

### Added
- **Mozilla Readability.js v0.6.0** vendored as primary content extractor — same algorithm used by Firefox Reader View. Produces clean, article-quality HTML on editorial pages.
- **Heuristic fallback** — link-density extractor still runs when Readability returns no content (nav-heavy or non-article pages), ensuring clean output on all page types.
- `result.metadata['extractor']` — reports which path ran (`"readability"` or `"heuristic"`).
- **77-test suite** — up from 23 tests:
  - `spec/browser_integration_spec.rb` — 15 browser integration tests using `data:` URLs (no network, works on CI)
  - `spec/url_normalizer_spec.rb` — 24 unit tests for URL normalization, www-stripping, tracking param removal
  - `spec/site_crawler_spec.rb` — 15 unit tests for BFS crawling, depth/page limits, error handling
- Integration tests run with plain `bundle exec rspec` — no `INTEGRATION=1` flag needed.

---

## [0.2.0] - 2025-12-01

### Changed
- **Migrated from Node.js/Playwright to Ferrum** (pure Ruby Chrome DevTools Protocol). Removes the Node.js subprocess entirely — no more `node/` directory, no npm, no inter-process HTTP.
- `RubyCrawl::Browser` replaces the old `ServiceClient` — all browser control is now in Ruby.
- `result.clean_html` and `result.raw_text` added — noise-stripped HTML and unfiltered body text.
- `result.clean_text` — lazily derived plain text from `clean_html`.
- `result.clean_markdown` — lazily converted Markdown from `clean_html`.

### Removed
- `node/` directory and all Node.js/Playwright code.
- `lib/rubycrawl/service_client.rb` — replaced by `lib/rubycrawl/browser.rb`.
- `rake rubycrawl:install` Playwright browser installer.

---

## [0.1.4] - 2025-10-15

### Fixed
- Version bump patch release.

---

## [0.1.3] - 2025-10-14

### Fixed
- Critical packaging fix — gem files were not included correctly in the gemspec.
- Added `.gitignore` entries to prevent build artifacts from being committed.

---

## [0.1.2] - 2025-10-12

### Added
- `result.clean_markdown` — Markdown conversion via `reverse_markdown`.
- Multi-page crawling via `RubyCrawl.crawl_site` with BFS and depth limiting.
- Improved `MarkdownConverter` with base URL resolution for relative links.
- `SiteCrawler::PageResult` — typed result object yielded per page during site crawls.

---

## [0.1.1] - 2025-10-05

### Added
- Link extraction — `result.links` returns `[{url, text, title, rel}]` for every `<a href>`.

---

## [0.1.0] - 2025-10-01

### Added
- Initial release.
- `RubyCrawl.crawl(url)` — crawls a URL with full JavaScript rendering via Playwright.
- `result.html` — full rendered page HTML.
- `result.metadata` — title, description, OG tags, Twitter cards, canonical URL, lang, charset.
- `result.final_url` — URL after redirects.
- Session management for reusing browser contexts across crawls.
- URL normalization and deduplication with tracking parameter removal.
- `RubyCrawl.configure` for global defaults.
- Rails integration via `RubyCrawl::Railtie`.
