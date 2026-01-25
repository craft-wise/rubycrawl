# Project: rubycrawl

## Purpose

Open-source, Playwright-based web crawler for Ruby designed for production use in Rails applications and Ruby projects.

## Inspiration

Inspired by [crawl4ai](https://github.com/unclecode/crawl4ai) (Python), but designed idiomatically for Ruby with first-class Rails support and production-ready architecture.

## Mission Statement

Bring crawl4ai-level accuracy and reliability to the Ruby ecosystem with a clean, minimal API that hides complexity while maintaining flexibility for advanced use cases.

## High-level Goals

1. **Accuracy First**: Provide crawl4ai-level accuracy using Playwright's battle-tested browser automation
2. **Clean Ruby API**: Expose a minimal, idiomatic Ruby interface that feels natural to Ruby developers
3. **Hide Complexity**: Abstract away Node.js and Playwright internals from end users
4. **Production-Ready**: Design for stability, observability, and deployment in real-world environments
5. **Rails Integration**: First-class support for Rails apps with generators, initializers, and conventions
6. **Correctness over Speed**: Prefer stability and reliability over raw performance
   - **Do not** use Ferrum or direct CDP integrations (too fragile)
   - **Do** use official Playwright Node.js bindings (most stable)
7. **Developer Experience**: Be easy to run locally, in CI/CD, and in production environments

## Non-goals

- **Not a SaaS**: This is a library, not a cloud service
- **No Infrastructure Lock-in**: No assumptions about cloud providers or hosting
- **No Vendor Lock-in**: Pure open source, no proprietary dependencies
- **No Built-in Services**: No user accounts, authentication, billing, dashboards, or API keys
- **No Custom Browser Engine**: Use Playwright's official browsers, not custom builds

## Architecture Overview

RubyCrawl uses a **dual-process architecture** that separates concerns between Ruby (orchestration) and Node.js (browser automation):

```
┌─────────────────────────────────────────────┐
│  Ruby Process (User's Application)           │
│  ┌─────────────────────────────────────┐   │
│  │  RubyCrawl Gem                        │   │
│  │  • Public API (RubyCrawl.crawl)       │   │
│  │  • Configuration management          │   │
│  │  • Result normalization              │   │
│  │  • Error handling & retries          │   │
│  │  • Content post-processing           │   │
│  └────────────┬────────────────────────┘   │
└───────────────┼─────────────────────────────┘
                │ HTTP/JSON (localhost:3344)
┌───────────────┼─────────────────────────────┐
│  Node.js Process (Auto-started by Ruby)      │
│  ┌────────────┴────────────────────────┐   │
│  │  Playwright Service                  │   │
│  │  • Browser lifecycle management      │   │
│  │  • Page navigation & waiting         │   │
│  │  • HTML/DOM extraction               │   │
│  │  • Resource blocking (perf)          │   │
│  │  • Network interception              │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Bundled Node Service**: Node.js source code is bundled with the gem (in `node/` directory)
   - **Why**: Ensures version compatibility and simplifies installation
   - **Trade-off**: Requires Node.js on user's system, but gives us stability

2. **Process Separation**: Ruby and Node.js run in separate processes
   - **Why**: Isolates browser crashes from Ruby process
   - **Trade-off**: HTTP overhead, but improves reliability

3. **Local HTTP Communication**: Ruby talks to Node via HTTP JSON on localhost
   - **Why**: Simple, well-understood protocol; easy to debug with curl
   - **Trade-off**: Not as fast as IPC, but fast enough for I/O-bound work

4. **Long-running Node Service**: Node process stays alive across multiple crawls
   - **Why**: Avoid browser launch overhead (1-2s per launch)
   - **Trade-off**: Need health checks and process management

5. **Browser Context Reuse**: Single browser, multiple contexts (one per crawl)
   - **Why**: Fast page isolation without full browser restart
   - **Trade-off**: Need proper cleanup to prevent memory leaks

### System Requirements

- **Ruby** >= 3.0 (host application)
- **Node.js** LTS (v18+) must be installed on the system
- **Playwright browsers** installed via `npx playwright install`
- **Disk space**: ~300MB for Chromium browser

## Ruby Layer Responsibilities

The Ruby gem (`lib/rubycrawl.rb`) is the **public interface** and **orchestration layer**:

### Core Responsibilities

1. **Public API**
   - Expose `RubyCrawl.crawl(url, **options)` class method
   - Provide `RubyCrawl.configure(**defaults)` for global settings
   - Return `RubyCrawl::Result` struct with normalized data

2. **Service Lifecycle Management**
   - Auto-start Node service on first crawl
   - Health check Node service before each request
   - Spawn Node process with proper environment variables
   - Handle Node service startup failures gracefully

3. **Configuration Management**
   - Merge global config with per-request options
   - Validate configuration parameters
   - Pass validated config to Node service

4. **HTTP Communication**
   - Send POST requests to Node service (`/crawl` endpoint)
   - Parse JSON responses from Node
   - Handle network errors and timeouts

5. **Error Handling**
   - Catch and wrap Node service errors
   - Provide meaningful error messages to users
   - Distinguish between network, browser, and content errors

6. **Content Post-processing** (Future)
   - Convert HTML to plain text
   - Convert HTML to Markdown
   - Extract and normalize links
   - Calculate content metrics

7. **Testing**
   - RSpec tests for all public methods
   - Mock Node service responses for fast tests
   - Integration tests with real Node service

### What Ruby Should NOT Do

- **Don't** interact with Playwright directly
- **Don't** parse HTML/DOM (delegate to Node or future Ruby processors)
- **Don't** manage browser processes (Node's job)
- **Don't** implement retry logic yet (keep it simple for v0.1)

## Node.js Layer Responsibilities

The Node service (`node/src/index.js`) is the **browser automation layer**:

### Core Responsibilities

1. **HTTP Server**
   - Listen on configurable port (default: 3344)
   - Expose `/health` GET endpoint for health checks
   - Expose `/crawl` POST endpoint for crawling
   - Return structured JSON responses only

2. **Browser Lifecycle**
   - Launch Playwright browser on startup (singleton)
   - Keep browser process alive across requests
   - Create new context per request (isolation)
   - Close contexts after each crawl (cleanup)
   - Handle browser crashes and restarts

3. **Page Navigation**
   - Navigate to URL with configurable `waitUntil`
   - Wait for page load events (`load`, `domcontentloaded`, `networkidle`)
   - Respect hard timeout (30s default)
   - Handle redirects and capture final URL

4. **Resource Optimization**
   - Block images, fonts, CSS, media when `block_resources: true`
   - Use Playwright's route interception
   - Reduce bandwidth and speed up crawls

5. **Content Extraction**
   - Extract raw HTML via `page.content()`
   - Capture HTTP status code
   - Record final URL after redirects
   - Return metadata (status, URL, timing)

6. **Error Handling**
   - Catch navigation errors (timeout, DNS, SSL)
   - Return structured error JSON
   - Log errors with context
   - Never crash the service

### What Node Should NOT Do

- **Don't** interpret content semantics (e.g., "is this a product page?")
- **Don't** extract structured data (leave for Ruby or future extractors)
- **Don't** implement business logic
- **Don't** persist state across requests (stateless per crawl)
- **Don't** use complex JavaScript frameworks (keep it simple)

## Design Principles

### Code Quality

1. **Simplicity over Cleverness**
   - Prefer explicit code over magic
   - Avoid metaprogramming unless it significantly improves DX
   - Use clear variable and method names
   - Example: `RubyCrawl.crawl(url)` not `RubyCrawl.(url)` or `RubyCrawl[url]`

2. **Avoid Premature Optimization**
   - Optimize for clarity first, performance second
   - Profile before optimizing
   - Document why optimizations exist
   - Example: Don't cache browser contexts until we prove it's needed

3. **Separation of Concerns**
   - Ruby handles orchestration, Node handles browsers
   - Never mix responsibilities
   - Each layer has a clear contract
   - Example: Ruby never calls Playwright APIs directly

### Observability

4. **Make Failures Debuggable**
   - Errors should include context (URL, config, timing)
   - Log at appropriate levels (debug, info, warn, error)
   - Provide actionable error messages
   - Example: "Node service failed to start" → "Node service failed to start. Is Node.js installed? Check $RUBYCRAWL_NODE_LOG"

5. **Structured Logging**
   - Use structured logs, not puts/console.log
   - Include timestamps, request IDs, and context
   - Make logs grep-friendly
   - Example: `[rubycrawl] crawl start url=https://example.com wait_until=load`

6. **Observable by Default**
   - Log important events (service start, crawl start/end, errors)
   - Include timing information
   - Make logs useful for debugging and monitoring

### Contributor Experience

7. **Be Friendly to Contributors**
   - Assume contributors are Ruby developers, not Node.js experts
   - Comment complex JavaScript code thoroughly
   - Provide examples in comments
   - Keep dependencies minimal

8. **Favor Maintainability**
   - Write code that's easy to change
   - Avoid tight coupling
   - Test important behaviors
   - Document architectural decisions (ADRs in comments)

9. **Progressive Disclosure**
   - Simple things should be simple
   - Advanced features should be possible
   - Don't expose complexity in the default API

## Public Ruby API Guidelines

### Core Principles

1. **Zero-Config Default**: The simplest usage should work out of the box
   ```ruby
   result = RubyCrawl.crawl("https://example.com")
   # No setup, no configuration, just works
   ```

2. **Progressive Enhancement**: Advanced options should be opt-in
   ```ruby
   # Simple
   result = RubyCrawl.crawl(url)

   # Configured
   result = RubyCrawl.crawl(url, wait_until: "networkidle")

   # Future: With actions (not yet implemented)
   result = RubyCrawl.crawl(url) do |page|
     page.click("#accept")
   end
   ```

3. **Hide Playwright Concepts**: Users shouldn't need to know Playwright
   - **Don't**: Expose `Page`, `Browser`, `Context` objects
   - **Do**: Provide Ruby-friendly abstractions
   - **Example**: `wait_until: "networkidle"` not `waitUntil: 'networkidle'`

4. **Intention-Revealing Names**: Method names should clearly state purpose
   - **Good**: `RubyCrawl.crawl(url)` — clear what it does
   - **Bad**: `RubyCrawl.fetch(url)` — too generic
   - **Bad**: `RubyCrawl.get(url)` — sounds like HTTP GET

5. **Return Rich Objects**: Don't return hashes, return structs/objects
   ```ruby
   result = RubyCrawl.crawl(url)
   result.html      # Clear attribute access
   result.metadata  # Not result[:metadata]
   ```

### Current API (v0.1.0)

#### Class-level API (Recommended)

```ruby
# Simple crawl (uses singleton instance)
result = RubyCrawl.crawl("https://example.com")

# Configure defaults
RubyCrawl.configure(
  wait_until: "load",
  block_resources: true
)

# Override per request
result = RubyCrawl.crawl(url, wait_until: "networkidle")
```

#### Instance API (Advanced)

```ruby
# Custom instance with specific config
crawler = RubyCrawl.new(
  host: "127.0.0.1",
  port: 3344,
  wait_until: "load"
)

result = crawler.crawl(url)
```

#### Result Object

```ruby
result = RubyCrawl.crawl(url)

# All attributes are accessible
result.html      # String: Full HTML content
result.text      # String: Plain text (coming soon)
result.markdown  # String: Markdown (coming soon)
result.links     # Array: Extracted links (coming soon)
result.metadata  # Hash: { status: 200, final_url: "..." }
```

### Future API (Planned)

#### Interactive Crawling (v0.2.0)

```ruby
result = RubyCrawl.crawl(url) do |page|
  page.click("#accept-cookies")
  page.scroll_to_bottom
  page.wait_for_selector(".content")
end
```

#### Session Management (v0.3.0)

```ruby
session = RubyCrawl::Session.new
session.crawl(login_url) do |page|
  page.fill("#username", "user")
  page.fill("#password", "pass")
  page.click("button[type=submit]")
end

result = session.crawl(protected_url)  # Uses cookies from login
```

### API Don'ts

- **Don't** return `nil` for missing data; return empty string/array/hash
- **Don't** raise for non-2xx HTTP status; return result with status in metadata
- **Don't** expose Playwright exceptions directly; wrap in RubyCrawl errors
- **Don't** mutate result objects after creation
- **Don't** use keyword args for positional data (url is positional, config is keyword)

## Node Service API Guidelines

The Node service communicates with Ruby via HTTP + JSON. Keep it simple and contract-based.

### Endpoint Contract

#### POST /crawl

**Request:**
```json
{
  "url": "https://example.com",
  "wait_until": "load",  // Optional: "load" | "domcontentloaded" | "networkidle"
  "block_resources": true  // Optional: boolean
}
```

**Success Response (200):**
```json
{
  "ok": true,
  "url": "https://example.com",
  "html": "<html>...</html>",
  "text": "",  // Future
  "markdown": "",  // Future
  "links": [],  // Future
  "metadata": {
    "status": 200,
    "final_url": "https://example.com"
  }
}
```

**Error Response (400/422):**
```json
{
  "error": "crawl_failed",
  "message": "Navigation timeout of 30000ms exceeded"
}
```

#### GET /health

**Response (200):**
```json
{
  "ok": true
}
```

### Implementation Guidelines

1. **Validate All Inputs**
   - Check `url` is present and non-empty
   - Validate `wait_until` against allowed values
   - Return 422 for validation errors

2. **Stateless Requests, Stateful Process**
   - Each request is independent (no session)
   - Browser process is shared across requests
   - Create new context per request

3. **Return Structured JSON Only**
   - Never return HTML errors or plain text
   - Always include `error` field on failure
   - Include `message` for debugging

4. **Handle Errors Gracefully**
   - Catch all exceptions
   - Map Playwright errors to generic codes
   - Log errors but don't crash the service

5. **Resource Management**
   - Always close page after crawl
   - Set hard timeout (30s)
   - Clean up on errors

## Performance Guidelines

### Browser Management

1. **Reuse Browser Process**
   - Launch browser once on service start
   - Keep it alive across requests
   - Don't restart unless crashed

2. **Context Pooling (Future)**
   - Current: Create context per request
   - Future: Pool contexts for speed
   - Always isolate requests

3. **Resource Blocking**
   - Block images, fonts, CSS by default (`block_resources: true`)
   - 2-3x faster crawls for content extraction
   - Make it configurable per request

4. **Concurrency Limits (Future)**
   - Limit concurrent pages (e.g., 5 max)
   - Queue requests if limit reached
   - Prevent memory exhaustion

### Performance Metrics

- First crawl: ~2s (includes browser launch)
- Subsequent crawls: ~500ms (browser reused)
- Target: <1s for static pages, <3s for SPAs

## Error Handling

### Ruby Layer

1. **Wrap Node Errors**
   ```ruby
   # Bad
   raise response["error"]

   # Good
   raise RubyCrawl::CrawlError, "Failed to crawl #{url}: #{response['message']}"
   ```

2. **Provide Context**
   - Include URL, config, and timing in errors
   - Distinguish between service errors and crawl errors

3. **Don't Swallow Errors**
   - Always propagate errors to users
   - Log before raising

### Node Layer

1. **Return Structured Errors**
   ```javascript
   // Bad
   throw new Error("Failed")

   // Good
   return json(res, 400, {
     error: "navigation_timeout",
     message: "Page took longer than 30s to load"
   })
   ```

2. **Error Categories**
   - `invalid_json`: Request body not valid JSON
   - `url_required`: Missing URL parameter
   - `navigation_timeout`: Page load timeout
   - `crawl_failed`: Generic crawl error

3. **Never Crash the Service**
   - Catch all errors in handlers
   - Log errors with context
   - Return error JSON, don't crash

## Testing Philosophy

### Ruby Tests (RSpec)

1. **Unit Tests for API**
   - Test public methods (`.crawl`, `.configure`)
   - Mock HTTP responses from Node
   - Fast tests (no real browsers)

2. **Integration Tests (Optional)**
   - Test with real Node service
   - Use VCR or WebMock for recording
   - Run in CI with Node installed

3. **Test Structure**
   ```ruby
   RSpec.describe RubyCrawl do
     describe ".crawl" do
       it "returns a Result object"
       it "handles Node service errors"
       it "merges config options"
     end
   end
   ```

### Node Tests (Future)

1. **Integration Tests**
   - Test `/crawl` endpoint with real Playwright
   - Verify HTML extraction
   - Test error scenarios

2. **Test Structure**
   ```javascript
   describe("POST /crawl", () => {
     it("extracts HTML from simple page")
     it("handles navigation timeout")
     it("validates required fields")
   })
   ```

### Testing Principles

- **Prefer Deterministic**: No sleep, use explicit waits
- **Avoid Flaky Tests**: No timing-based assertions
- **Mock External Services**: Don't test example.com
- **Test Error Paths**: Errors are important

## Documentation Expectations

### README.md

- **Installation**: Step-by-step for Rails and non-Rails
- **Quick Start**: Copy-paste example that works
- **Requirements**: Explicit about Node.js dependency
- **Configuration**: Document all options with examples
- **Troubleshooting**: Common errors and solutions

### Code Comments

- **Why, not What**: Explain rationale, not mechanics
- **Architecture Decisions**: Document trade-offs
- **TODOs**: Mark future work clearly
- **Examples**: Include usage examples in comments

### API Documentation (Future)

- YARD docs for public methods
- Type signatures for clarity
- Examples for each method

## Contribution Guidelines

### Mindset

1. **Ruby-First**: Contributors are Ruby developers
   - Comment JavaScript code thoroughly
   - Explain Node.js concepts
   - Provide learning resources

2. **Avoid Cleverness**
   - Use simple JavaScript
   - No advanced features unless necessary
   - Prefer clarity over terseness

3. **Maintainability Wins**
   - Code should be easy to change
   - Refactor as you go
   - Leave code better than you found it

### Code Style

**Ruby:**
- Follow RuboCop defaults
- Use 2-space indentation
- Prefer explicit over implicit

**JavaScript:**
- Use ESLint with recommended config
- Prefer `const` over `let`
- Use async/await, not callbacks

### Pull Request Guidelines

1. **Include Tests**: All new features need tests
2. **Update Docs**: Update README if API changes
3. **Follow Conventions**: Match existing code style
4. **Keep PRs Small**: Focus on one thing
5. **Write Good Commits**: Explain why, not what

## Versioning & Compatibility

### Semantic Versioning

Follow [SemVer 2.0.0](https://semver.org/):

- **Major (1.0.0)**: Breaking public API changes
- **Minor (0.1.0)**: New features, backward compatible
- **Patch (0.0.1)**: Bug fixes, backward compatible

### Version Compatibility

1. **Ruby Gem & Node Service**
   - Both versioned together (same version number)
   - Node service bundled with gem
   - No separate version mismatches

2. **Ruby Version Support**
   - Support Ruby 3.0+ (current policy)
   - Drop versions with major bump
   - Test on multiple Ruby versions in CI

3. **Node.js Version Support**
   - Require Node.js LTS (v18+)
   - Document in README
   - Test on multiple Node versions

### Breaking Changes

**Require a major version bump:**
- Removing public methods
- Changing method signatures
- Changing return types
- Removing configuration options

**Don't require a major bump:**
- Adding new methods
- Adding new config options (with defaults)
- Deprecating with warnings
- Internal refactoring

### Deprecation Policy

1. **Warn First**: Add deprecation warnings in minor release
2. **Wait One Major**: Keep deprecated code for at least one major version
3. **Document**: List deprecations in CHANGELOG
4. **Provide Migration Path**: Show users how to update

Example:
```ruby
# v0.5.0: Deprecate old method
def old_method
  warn "DEPRECATION: old_method is deprecated, use new_method instead"
  new_method
end

# v1.0.0: Remove old method
# (old_method no longer exists)
```

## Release Checklist

Before releasing a new version:

1. [ ] Update `lib/rubycrawl/version.rb`
2. [ ] Update `node/package.json` version
3. [ ] Update CHANGELOG.md
4. [ ] Run full test suite
5. [ ] Test installation in fresh environment
6. [ ] Update README if needed
7. [ ] Create git tag
8. [ ] Build and push gem
9. [ ] Create GitHub release with notes
