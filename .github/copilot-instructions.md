# Project: rubycrawl

## Purpose

Open-source, pure Ruby web crawler with full JavaScript rendering, designed for RAG (Retrieval-Augmented Generation) pipelines and production use in Rails applications. Uses [Ferrum](https://github.com/rubycdp/ferrum) (pure Ruby Chrome DevTools Protocol client) for browser automation — no Node.js, no external processes.

## Vision

Bring production-grade, Ferrum-powered web crawling to the Ruby ecosystem with a clean, minimal API that hides complexity while maintaining flexibility for advanced use cases.

## Mission Statement

Provide Ruby developers with a reliable, accurate web crawler that handles modern JavaScript-heavy websites with the same ease and elegance they expect from Ruby tools. Make browser automation accessible without requiring Node.js expertise. Produce RAG-ready output (clean text, markdown) as first-class outputs.

## High-level Goals

1. **Accuracy First**: Playwright-quality rendering via Ferrum's battle-tested Chrome DevTools Protocol client
2. **Clean Ruby API**: Expose a minimal, idiomatic Ruby interface that feels natural to Ruby developers
3. **Hide Complexity**: Abstract away Ferrum and Chrome internals from end users
4. **Production-Ready**: Design for stability, observability, and deployment in real-world environments
5. **Rails Integration**: First-class support for Rails apps with generators, initializers, and conventions
6. **Correctness over Speed**: Prefer stability and reliability over raw performance
   - **Do** use Ferrum (pure Ruby CDP client) for browser automation
   - **Do not** use Node.js, Playwright Node bindings, direct CDP calls, or Ferrum as a public API
7. **RAG-first Output**: `clean_text` and `clean_markdown` are primary outputs — optimised for LLM consumption
8. **Crawling-First Focus**: rubycrawl is for **crawling public websites**, not interactive browser automation
   - For interactive features (click, scroll, forms, custom JS), use Ferrum or Playwright Ruby bindings directly
   - Keep scope focused on content extraction and multi-page crawling

## Non-goals

- **Not a SaaS**: This is a library, not a cloud service
- **No Infrastructure Lock-in**: No assumptions about cloud providers or hosting
- **No Vendor Lock-in**: Pure open source, no proprietary dependencies
- **No Built-in Services**: No user accounts, authentication, billing, dashboards, or API keys
- **No Node.js**: Pure Ruby — no npm, no separate processes, no port management

## Architecture Overview

rubycrawl uses a **single-process pure Ruby architecture**. Ferrum manages Chrome directly via CDP:

```
RubyCrawl (lib/rubycrawl.rb)       ← public API
  ↓
Browser (lib/rubycrawl/browser.rb) ← Ferrum wrapper, all browser logic lives here
  ↓
Ferrum::Browser                    ← Chrome DevTools Protocol (pure Ruby)
  ↓
Chromium                           ← headless browser (managed by Ferrum)
```

### Key Architectural Decisions

1. **Pure Ruby via Ferrum**: No Node.js or npm required
   - **Why**: Deploys like any other gem; same Chrome DevTools Protocol under the hood as Playwright
   - **Trade-off**: Ruby GIL applies, but I/O-bound crawling is still efficient

2. **Singleton Browser Instance**: One `Ferrum::Browser` launched lazily, reused across crawls
   - **Why**: Avoid 1–2s browser launch overhead per crawl
   - **Trade-off**: Need mutex for thread safety; crashes reset all contexts

3. **Isolated Page per Crawl**: Each `Browser#crawl` call creates a fresh context via `create_page(new_context: true)`
   - **Why**: Prevents cookie/storage leakage between crawls
   - **Trade-off**: Slight overhead vs. reusing contexts

4. **JS Evaluation for Extraction**: All extraction (metadata, links, clean content) runs via `page.evaluate()`
   - **Why**: DOM access is more reliable than HTML parsing for rendered pages
   - **Trade-off**: Requires careful IIFE wrapping for Ferrum's expression evaluator

5. **Vendored Readability.js**: Mozilla Readability.js v0.6.0 bundled in `lib/rubycrawl/browser/readability.js`
   - **Why**: Article-quality extraction without external runtime dependencies
   - **Trade-off**: Manual updates needed for new Readability versions

### System Requirements

- **Ruby** >= 3.0 (host application)
- **Chrome/Chromium** — auto-managed by Ferrum (downloads on first use)
- No Node.js, npm, or separate processes required

## Ruby Layer Responsibilities

The gem is organised into focused modules:

### Core Components

**Main Entry Point** (`lib/rubycrawl.rb`):
- Public API: `RubyCrawl.crawl(url, **options)` and `RubyCrawl.crawl_site(url, **options, &block)`
- Configuration management via `RubyCrawl.configure(**defaults)`
- Orchestrates browser, validation, retry logic, and result building

**Supporting Modules** (`lib/rubycrawl/`):

1. **errors.rb** — Custom exception hierarchy
   - `Error` (base class)
   - `ServiceError` — browser failed to launch or crashed
   - `NavigationError` — page navigation failures (bad URL, HTTP error, SSL)
   - `TimeoutError` — page load timed out
   - `ConfigurationError` — invalid URL or config value

2. **helpers.rb** — Validation and utility methods
   - URL validation (HTTP/HTTPS only)
   - `wait_until` option validation
   - Crawler options builder

3. **browser.rb** — Ferrum wrapper; all browser interaction lives here
   - Lazy-initialises singleton `Ferrum::Browser` (mutex-protected for Puma)
   - Creates isolated page contexts per crawl (`new_context: true`)
   - Runs JS extraction via `page.evaluate()`
   - Handles resource blocking via Ferrum's network intercept
   - Maps Ferrum exceptions to rubycrawl error hierarchy

4. **browser/extraction.rb** — JS extraction constants (all IIFEs for Ferrum compatibility)
   - `EXTRACT_METADATA_JS` — title, description, OG tags, Twitter cards, canonical, lang, charset
   - `EXTRACT_LINKS_JS` — all `a[href]` with url/text/title/rel
   - `EXTRACT_RAW_TEXT_JS` — `body.innerText` (unfiltered)
   - `EXTRACT_CONTENT_JS` — Mozilla Readability.js (primary) with link-density heuristic fallback; returns `{ cleanHtml, extractor }`

5. **browser/readability.js** — Vendored Mozilla Readability.js v0.6.0

6. **robots_parser.rb** — Fetches and parses `robots.txt`
   - `RobotsParser.fetch(base_url)` — downloads via `Net::HTTP`, 5s timeout, fails open on error
   - `allowed?(url)` — checks `User-agent: *` rules; Allow takes precedence over Disallow
   - `crawl_delay` — returns `Crawl-delay` as Float or nil

7. **url_normalizer.rb** — URL normalization and deduplication
   - Normalizes URLs (lowercase host/scheme, remove fragments)
   - Removes tracking parameters (`utm_*`, `fbclid`, `gclid`)
   - Sorts query params for canonical form
   - Resolves relative URLs to absolute
   - `same_host?` treats www and non-www as the same host

8. **markdown_converter.rb** — HTML to Markdown conversion
   - Uses `reverse_markdown` gem with GitHub-flavored output
   - Resolves relative URLs in markdown to absolute
   - Lazy — only loaded when `clean_markdown` is accessed

9. **result.rb** — Immutable value object returned from every crawl
   - `html` — full raw HTML
   - `raw_text` — unfiltered `body.innerText`
   - `clean_html` — noise-stripped HTML (from Readability or heuristic)
   - `clean_text` — lazy: derived from `clean_html` via block-level newline replacement
   - `clean_markdown` — lazy: derived from `clean_html` via `MarkdownConverter`
   - `links` — array of `{ 'url', 'text', 'title', 'rel' }` hashes
   - `metadata` — status, final_url, title, description, og_*, twitter_*, canonical, lang, charset
   - `final_url` — shortcut for `metadata['final_url']`

10. **site_crawler.rb** — BFS multi-page crawler
    - Takes a `RubyCrawl` client instance and options
    - Yields `SiteCrawler::PageResult` (same interface as `Result` + `depth` attribute)
    - Deduplicates via `Set` of normalized URLs
    - Silently skips failed pages (logs warning), continues crawling
    - Handles `respect_robots_txt: true` — fetches robots.txt once, skips disallowed URLs, auto-sleeps `Crawl-delay`

### What Ruby Should NOT Do

- **Don't** interact with Chrome or CDP directly — use Ferrum through `Browser`
- **Don't** parse HTML/DOM in Ruby for extraction — delegate to JS via `page.evaluate()`
- **Don't** manage Chrome processes — Ferrum handles lifecycle
- **Don't** put multi-page logic in the main class — use `SiteCrawler`

## Public Ruby API

### Core Principles

1. **Zero-Config Default**: The simplest usage works out of the box
   ```ruby
   result = RubyCrawl.crawl("https://example.com")
   # No setup, no configuration, just works
   ```

2. **Progressive Enhancement**: Advanced options are opt-in
   ```ruby
   # Simple
   result = RubyCrawl.crawl(url)

   # With options
   result = RubyCrawl.crawl(url, wait_until: "networkidle", block_resources: true)

   # Global defaults
   RubyCrawl.configure(block_resources: true, timeout: 60)
   ```

3. **Hide Ferrum Concepts**: Users should never need to know Ferrum exists
   - **Don't** expose `Ferrum::Browser`, `Ferrum::Page`, or CDP objects
   - **Do** provide Ruby-friendly abstractions

4. **Return Rich Objects**: Return value objects, not hashes
   ```ruby
   result.html           # not result[:html]
   result.clean_markdown # not result['markdown']
   ```

### Single-Page API

```ruby
# Simple crawl (uses singleton client)
result = RubyCrawl.crawl("https://example.com")

# Result fields
result.html           # String: Full raw HTML with JS rendered
result.raw_text       # String: Unfiltered body.innerText
result.clean_text     # String: Noise-stripped plain text (RAG-ready)
result.clean_html     # String: Noise-stripped HTML (Readability or heuristic)
result.clean_markdown # String: Lazy — converted from clean_html on first access
result.links          # Array: [{ 'url' => '...', 'text' => '...', 'title' => nil, 'rel' => nil }, ...]
result.metadata       # Hash: { 'status' => 200, 'final_url' => '...', 'title' => '...', ... }
result.final_url      # String: Shortcut for metadata['final_url']
```

### Configuration Options

```ruby
RubyCrawl.configure(
  wait_until:         "load",   # "load" | "domcontentloaded" | "networkidle" | "commit" | nil
  block_resources:    true,     # Block images/fonts/CSS/media for speed
  max_attempts:       3,        # Auto-retry with exponential backoff
  timeout:            30,       # Browser navigation timeout in seconds
  respect_robots_txt: false,    # Honour robots.txt Disallow rules and Crawl-delay
  headless:           true,     # Run Chrome headless (set false for debugging)
  browser_options:    {}        # Passed directly to Ferrum::Browser options
)
```

### Multi-Page API

```ruby
# BFS site crawl — yields each page as crawled (streaming)
RubyCrawl.crawl_site("https://example.com",
  max_pages:          50,    # Maximum pages to crawl
  max_depth:          3,     # Maximum link depth from start URL
  same_host_only:     true,  # Only follow links on same domain
  respect_robots_txt: false  # Honour robots.txt
) do |page|
  page.url           # String: Final URL after redirects
  page.html          # String: Full HTML
  page.clean_text    # String: Noise-stripped plain text
  page.clean_markdown # String: Lazy — converted from clean_html
  page.links         # Array: Extracted link hashes
  page.metadata      # Hash: Status, final_url, title, etc.
  page.depth         # Integer: Link depth from start URL
end
```

### API Don'ts

- **Don't** return `nil` for missing data — return empty string/array/hash
- **Don't** raise for non-2xx HTTP status — return result with status in metadata
- **Don't** expose Ferrum exceptions directly — wrap in rubycrawl errors
- **Don't** mutate result objects after creation
- **Don't** use keyword args for positional data (`url` is positional, config is keyword)

## Design Principles

### Code Quality

1. **Simplicity over Cleverness**
   - Prefer explicit code over metaprogramming
   - Clear variable and method names
   - Example: `RubyCrawl.crawl(url)` not `RubyCrawl.(url)`

2. **Avoid Premature Optimization**
   - Optimize for clarity first, performance second
   - Profile before optimizing
   - Document why optimizations exist

3. **Separation of Concerns**
   - Ruby handles orchestration, Ferrum/Chrome handles rendering
   - Never mix responsibilities
   - `Browser` is the only class that knows Ferrum exists

4. **RAG-first Output**
   - `clean_text` and `clean_markdown` are primary outputs
   - Optimised for LLM consumption, not raw HTML fidelity

### Observability

5. **Make Failures Debuggable**
   - Errors should include context (URL, config, timing)
   - Provide actionable error messages
   - Example: "Browser error: ..." not just "failed"

6. **Structured Logging**
   - Use `warn "[rubycrawl] ..."` format for warnings
   - Include URL, attempt number, backoff time in retry logs

### Contributor Experience

7. **Ruby-First**: This is a Ruby gem — contributors should not need Node.js expertise
8. **Maintainability Wins**: Code should be easy to change

## Error Handling

### Error Hierarchy

```
StandardError
  └── RubyCrawl::Error
        ├── ServiceError      — browser failed to launch or crashed
        ├── NavigationError   — page navigation failed (bad URL, timeout, HTTP error)
        ├── TimeoutError      — page load timed out
        └── ConfigurationError — invalid URL or option value
```

### Ferrum Exception Mapping (in `browser.rb`)

| Ferrum exception | rubycrawl exception |
|------------------|---------------------|
| `Ferrum::TimeoutError` | `RubyCrawl::TimeoutError` |
| `Ferrum::StatusError` | `RubyCrawl::NavigationError` |
| `Ferrum::NodeNotFoundError` | `RubyCrawl::NavigationError` |
| `Ferrum::Error` (base) | `RubyCrawl::ServiceError` |

### Ruby Layer Rules

1. Always wrap Ferrum errors — never let them surface to users
2. Retry only `ServiceError` and `TimeoutError` (transient); not `NavigationError` or `ConfigurationError`
3. Always close pages in `ensure` blocks — even on error

## Performance Guidelines

1. **Reuse Browser Instance** — launched once, kept alive across crawls
2. **Resource Blocking** — `block_resources: true` blocks images/fonts/CSS/media; 2–3x faster for text extraction
3. **Isolated Contexts** — each crawl gets its own context; no shared cookies/storage

## Testing Philosophy

### Test Types

- **Unit tests** (`spec/rubycrawl_spec.rb`, `spec/url_normalizer_spec.rb`, `spec/site_crawler_spec.rb`): mock the browser, fast, no Chrome needed
- **Browser integration tests** (`spec/browser_integration_spec.rb`): real Chrome, use `data:` URLs — no network required, works offline and in CI

### Running Tests

```bash
bundle exec rspec       # All tests (unit + browser integration)
bundle exec rubocop     # Lint
```

### Testing Principles

- **No real network**: Unit tests mock browser responses; integration tests use `data:` URLs
- **Prefer deterministic**: No sleep, use explicit waits
- **Avoid flaky tests**: No timing-based assertions
- **Test error paths**: Error handling is as important as the happy path

## Code Review Checklist

- [ ] Public API is clean and Ruby-idiomatic?
- [ ] Ferrum complexity is hidden from users (not exposed in public interface)?
- [ ] All browser resources cleaned up (pages closed in `ensure` blocks)?
- [ ] Ferrum exceptions mapped to rubycrawl error hierarchy?
- [ ] Changes backward compatible (or version bump justified)?
- [ ] README updated if API changed?
- [ ] Tests cover new behaviour including error paths?

## Versioning

Follow [SemVer 2.0.0](https://semver.org/):

- **Major**: Breaking public API changes
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes, backward compatible

**Breaking changes** (require major bump): removing public methods, changing method signatures, changing return types.

**Non-breaking** (no major bump needed): adding new methods, adding new config options with defaults, deprecating with warnings, internal refactoring.

## Release Checklist

1. [ ] Update `lib/rubycrawl/version.rb`
2. [ ] Update `CHANGELOG.md`
3. [ ] Run full test suite (`bundle exec rspec`)
4. [ ] Test installation in fresh environment
5. [ ] Update README if API changed
6. [ ] Create git tag
7. [ ] Build and push gem
8. [ ] Create GitHub release with notes
