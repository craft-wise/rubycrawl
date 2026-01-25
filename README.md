# rubycrawl

[![Gem Version](https://badge.fury.io/rb/rubycrawl.svg)](https://badge.fury.io/rb/rubycrawl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Playwright-based web crawler for Ruby** — Inspired by [crawl4ai](https://github.com/unclecode/crawl4ai) (Python), designed idiomatically for Ruby with production-ready features.

RubyCrawl provides accurate, JavaScript-enabled web scraping using Playwright's battle-tested browser automation, wrapped in a clean Ruby API. Perfect for extracting content from modern SPAs and dynamic websites.

## Features

- **Playwright-powered**: Real browser automation for JavaScript-heavy sites
- **Production-ready**: Designed for Rails apps and production environments
- **Simple API**: Clean, minimal Ruby interface — zero Playwright knowledge required
- **Resource optimization**: Built-in resource blocking for faster crawls
- **Auto-managed browsers**: Browser process reuse and automatic lifecycle management
- **Content extraction**: HTML, links, and Markdown conversion
- **Multi-page crawling**: BFS crawler with depth limits and deduplication
- **Rails integration**: First-class Rails support with generators and initializers

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Basic Crawling](#basic-crawling)
  - [Multi-Page Crawling](#multi-page-crawling)
  - [Configuration](#configuration)
  - [Result Object](#result-object)
- [Rails Integration](#rails-integration)
- [Production Deployment](#production-deployment)
- [Architecture](#architecture)
- [Performance](#performance)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Requirements

- **Ruby** >= 3.0
- **Node.js** LTS (v18+ recommended) — required for the bundled Playwright service

### Add to Gemfile

```ruby
gem "rubycrawl"
```

Then install:

```bash
bundle install
```

### Install Playwright browsers

After bundling, install the Playwright browsers:

```bash
bundle exec rake rubycrawl:install
```

This command:

- Installs Node.js dependencies in the bundled `node/` directory
- Downloads Playwright browsers (Chromium, Firefox, WebKit)
- Creates a Rails initializer (if using Rails)

## Quick Start

```ruby
require "rubycrawl"

# Simple crawl
result = RubyCrawl.crawl("https://example.com")

# Access extracted content
puts result.html      # Raw HTML content
puts result.markdown  # Converted to Markdown
puts result.links     # Extracted links from the page
puts result.metadata  # Status code, final URL, etc.
```

## Usage

### Basic Crawling

The simplest way to crawl a URL:

```ruby
result = RubyCrawl.crawl("https://example.com")

# Access the results
result.html      # => "<html>...</html>"
result.markdown  # => "# Example Domain\n\nThis domain is..." (lazy-loaded)
result.links     # => [{ "url" => "https://...", "text" => "More info" }, ...]
result.metadata  # => { "status" => 200, "final_url" => "https://example.com" }
result.text      # => "" (coming soon)
```

### Multi-Page Crawling

Crawl an entire site following links with BFS (breadth-first search):

```ruby
# Crawl up to 100 pages, max 3 links deep
RubyCrawl.crawl_site("https://example.com", max_pages: 100, max_depth: 3) do |page|
  # Each page is yielded as it's crawled (streaming)
  puts "Crawled: #{page.url} (depth: #{page.depth})"
  
  # Save to database
  Page.create!(
    url: page.url,
    html: page.html,
    markdown: page.markdown,
    depth: page.depth
  )
end
```

#### Multi-Page Options

| Option | Default | Description |
|--------|---------|-------------|
| `max_pages` | 50 | Maximum number of pages to crawl |
| `max_depth` | 3 | Maximum link depth from start URL |
| `same_host_only` | true | Only follow links on the same domain |
| `wait_until` | inherited | Page load strategy |
| `block_resources` | inherited | Block images/fonts/CSS |

#### Page Result Object

The block receives a `PageResult` with:

```ruby
page.url       # String: Final URL after redirects
page.html      # String: Full HTML content  
page.markdown  # String: Lazy-converted Markdown
page.links     # Array: URLs extracted from page
page.metadata  # Hash: HTTP status, final URL, etc.
page.depth     # Integer: Link depth from start URL
```

### Configuration

#### Global Configuration

Set default options that apply to all crawls:

```ruby
RubyCrawl.configure(
  wait_until: "networkidle",  # Wait until network is idle
  block_resources: true        # Block images, fonts, CSS for speed
)

# All subsequent crawls use these defaults
result = RubyCrawl.crawl("https://example.com")
```

#### Per-Request Options

Override defaults for specific requests:

```ruby
# Use global defaults
result = RubyCrawl.crawl("https://example.com")

# Override for this request only
result = RubyCrawl.crawl(
  "https://example.com",
  wait_until: "domcontentloaded",
  block_resources: false
)
```

#### Configuration Options

| Option            | Values                                          | Default  | Description                                       |
| ----------------- | ----------------------------------------------- | -------- | ------------------------------------------------- |
| `wait_until`      | `"load"`, `"domcontentloaded"`, `"networkidle"` | `"load"` | When to consider page loaded                      |
| `block_resources` | `true`, `false`                                 | `true`   | Block images, fonts, CSS, media for faster crawls |

**Wait strategies explained:**

- `load` — Wait for the load event (fastest, good for static sites)
- `domcontentloaded` — Wait for DOM ready (medium speed)
- `networkidle` — Wait until no network requests for 500ms (slowest, best for SPAs)

### Result Object

The crawl result is a `RubyCrawl::Result` object with these attributes:

```ruby
result = RubyCrawl.crawl("https://example.com")

result.html      # String: Raw HTML content from page
result.markdown  # String: Markdown conversion (lazy-loaded on first access)
result.links     # Array: Extracted links with url and text
result.text      # String: Plain text (coming soon)
result.metadata  # Hash: Comprehensive metadata (see below)
```

#### Links Format

```ruby
result.links
# => [
#   { "url" => "https://example.com/about", "text" => "About Us" },
#   { "url" => "https://example.com/contact", "text" => "Contact" },
#   ...
# ]
```

#### Markdown Conversion

Markdown is **lazy-loaded** — conversion only happens when you access `.markdown`:

```ruby
result = RubyCrawl.crawl(url)
result.html       # ✅ No overhead
result.markdown   # ⬅️ Conversion happens here (first call only)
result.markdown   # ✅ Cached, instant
```

Uses [reverse_markdown](https://github.com/xijo/reverse_markdown) with GitHub-flavored output.

#### Metadata Fields

The `metadata` hash includes HTTP and HTML metadata:

```ruby
result.metadata
# => {
#   "status" => 200,                 # HTTP status code
#   "final_url" => "https://...",    # Final URL after redirects
#   "title" => "Page Title",         # <title> tag
#   "description" => "...",          # Meta description
#   "keywords" => "ruby, web",       # Meta keywords
#   "author" => "Author Name",       # Meta author
#   "og_title" => "...",             # Open Graph title
#   "og_description" => "...",       # Open Graph description
#   "og_image" => "https://...",     # Open Graph image
#   "og_url" => "https://...",       # Open Graph URL
#   "og_type" => "website",          # Open Graph type
#   "twitter_card" => "summary",     # Twitter card type
#   "twitter_title" => "...",        # Twitter title
#   "twitter_description" => "...",  # Twitter description
#   "twitter_image" => "https://...",# Twitter image
#   "canonical" => "https://...",    # Canonical URL
#   "lang" => "en",                  # Page language
#   "charset" => "UTF-8"             # Character encoding
# }
```

Note: All HTML metadata fields may be `null` if not present on the page.

### Error Handling

RubyCrawl provides specific exception classes for different error scenarios:

```ruby
begin
  result = RubyCrawl.crawl(url)
rescue RubyCrawl::ConfigurationError => e
  # Invalid URL or configuration
  puts "Configuration error: #{e.message}"
rescue RubyCrawl::TimeoutError => e
  # Page load timeout or network timeout
  puts "Timeout: #{e.message}"
rescue RubyCrawl::NavigationError => e
  # Page navigation failed (404, DNS error, SSL error, etc.)
  puts "Navigation failed: #{e.message}"
rescue RubyCrawl::ServiceError => e
  # Node service unavailable or crashed
  puts "Service error: #{e.message}"
rescue RubyCrawl::Error => e
  # Catch-all for any RubyCrawl error
  puts "Crawl error: #{e.message}"
end
```

**Exception Hierarchy:**
- `RubyCrawl::Error` (base class)
  - `RubyCrawl::ConfigurationError` - Invalid URL or configuration
  - `RubyCrawl::TimeoutError` - Timeout during crawl
  - `RubyCrawl::NavigationError` - Page navigation failed
  - `RubyCrawl::ServiceError` - Node service issues

**Automatic Retry:** RubyCrawl automatically retries transient failures (service errors, timeouts) up to 3 times with exponential backoff (2s, 4s, 8s). Configure with:

```ruby
RubyCrawl.configure(max_retries: 5)
# or per-request
RubyCrawl.crawl(url, retries: 1)  # Disable retry
```

## Rails Integration

### Installation

Run the installer in your Rails app:

```bash
bundle exec rake rubycrawl:install
```

This creates `config/initializers/rubycrawl.rb`:

```ruby
# frozen_string_literal: true

# rubycrawl default configuration
RubyCrawl.configure(
  wait_until: "load",
  block_resources: true
)
```

### Usage in Rails

```ruby
# In a controller, service, or background job
class ContentScraperJob < ApplicationJob
  def perform(url)
    result = RubyCrawl.crawl(url)

    # Save to database
    ScrapedContent.create!(
      url: url,
      html: result.html,
      status: result.metadata[:status]
    )
  end
end
```

## Production Deployment

### Pre-deployment Checklist

1. **Install Node.js** on your production servers (LTS version recommended)
2. **Run installer** during deployment:
   ```bash
   bundle exec rake rubycrawl:install
   ```
3. **Set environment variables** (optional):
   ```bash
   export RUBYCRAWL_NODE_BIN=/usr/bin/node  # Custom Node.js path
   export RUBYCRAWL_NODE_LOG=/var/log/rubycrawl.log  # Service logs
   ```

### Docker Example

```dockerfile
FROM ruby:3.2

# Install Node.js LTS
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs

# Install system dependencies for Playwright
RUN npx playwright install-deps

WORKDIR /app
COPY Gemfile* ./
RUN bundle install

# Install Playwright browsers
RUN bundle exec rake rubycrawl:install

COPY . .
CMD ["rails", "server"]
```

### Heroku Deployment

Add the Node.js buildpack:

```bash
heroku buildpacks:add heroku/nodejs
heroku buildpacks:add heroku/ruby
```

Add to `package.json` in your Rails root:

```json
{
  "engines": {
    "node": "18.x"
  }
}
```

### Performance Tips

- **Reuse instances**: Use the class-level `RubyCrawl.crawl` method (recommended) rather than creating new instances
- **Resource blocking**: Keep `block_resources: true` for 2-3x faster crawls when you don't need images/CSS
- **Concurrency**: Use background jobs (Sidekiq, etc.) for parallel crawling
- **Browser reuse**: The first crawl is slower due to browser launch; subsequent crawls reuse the process

## Architecture

RubyCrawl uses a **dual-process architecture**:

```
┌─────────────────────────────────────────────┐
│  Ruby Process (Your Application)            │
│  ┌─────────────────────────────────────┐   │
│  │  RubyCrawl Gem                        │   │
│  │  • Public API                        │   │
│  │  • Result normalization              │   │
│  │  • Error handling                    │   │
│  └────────────┬────────────────────────┘   │
└───────────────┼─────────────────────────────┘
                │ HTTP/JSON (localhost:3344)
┌───────────────┼─────────────────────────────┐
│  Node.js Process (Auto-started)              │
│  ┌────────────┴────────────────────────┐   │
│  │  Playwright Service                  │   │
│  │  • Browser management                │   │
│  │  • Page navigation                   │   │
│  │  • HTML extraction                   │   │
│  │  • Resource blocking                 │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Why this architecture?**

- **Separation of concerns**: Ruby handles orchestration, Node handles browsers
- **Stability**: Playwright's official Node.js bindings are most reliable
- **Performance**: Long-running browser process, reused across requests
- **Simplicity**: No C extensions, pure Ruby + bundled Node service

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for detailed architecture documentation.

## Performance

### Benchmarks

Typical crawl times (M1 Mac, fast network):

| Page Type   | First Crawl | Subsequent | Config                      |
| ----------- | ----------- | ---------- | --------------------------- |
| Static HTML | ~2s         | ~500ms     | `block_resources: true`     |
| SPA (React) | ~3s         | ~1.2s      | `wait_until: "networkidle"` |
| Heavy site  | ~4s         | ~2s        | `block_resources: false`    |

**Note**: First crawl includes browser launch time (~1.5s). Subsequent crawls reuse the browser.

### Optimization Tips

1. **Enable resource blocking** for content-only extraction:

   ```ruby
   RubyCrawl.configure(block_resources: true)
   ```

2. **Use appropriate wait strategy**:
   - Static sites: `wait_until: "load"`
   - SPAs: `wait_until: "networkidle"`

3. **Batch processing**: Use background jobs for concurrent crawling:
   ```ruby
   urls.each { |url| CrawlJob.perform_later(url) }
   ```

## Development

### Setup

```bash
git clone git@github.com:craft-wise/rubycrawl.git
cd rubycrawl
bin/setup  # Installs dependencies and sets up Node service
```

### Running Tests

```bash
bundle exec rspec
```

### Manual Testing

```bash
# Terminal 1: Start Node service manually (optional)
cd node
npm start

# Terminal 2: Ruby console
bin/console
> result = RubyCrawl.crawl("https://example.com")
> puts result.html
```

### Project Structure

```
rubycrawl/
├── lib/
│   ├── rubycrawl.rb              # Main gem entry point
│   ├── rubycrawl/
│   │   ├── version.rb           # Gem version
│   │   ├── railtie.rb           # Rails integration
│   │   └── tasks/
│   │       └── install.rake     # Installation task
├── node/
│   ├── src/
│   │   └── index.js             # Playwright HTTP service
│   ├── package.json
│   └── README.md
├── spec/                        # RSpec tests
├── .github/
│   └── copilot-instructions.md  # GitHub Copilot guidelines
├── CLAUDE.md                    # Claude AI guidelines
└── README.md
```

## Roadmap

### Current (v0.1.0)

- [x] HTML extraction
- [x] Link extraction
- [x] Markdown conversion (lazy-loaded)
- [x] Multi-page crawling with BFS
- [x] URL normalization and deduplication
- [x] Basic metadata (status, final URL)
- [x] Resource blocking
- [x] Rails integration

### Coming Soon

- [ ] Plain text extraction
- [ ] Screenshot capture
- [ ] Custom JavaScript execution
- [ ] Session/cookie support
- [ ] Proxy support
- [ ] Robots.txt support

## Contributing

Contributions are welcome! Please read our [contribution guidelines](.github/copilot-instructions.md) first.

### Development Philosophy

- **Simplicity over cleverness**: Prefer clear, explicit code
- **Stability over speed**: Correctness first, optimization second
- **Ruby-first**: Hide Node.js/Playwright complexity from users
- **No vendor lock-in**: Pure open source, no SaaS dependencies

## Comparison with crawl4ai

| Feature             | crawl4ai (Python) | rubycrawl (Ruby) |
| ------------------- | ----------------- | ---------------- |
| Browser automation  | Playwright        | Playwright       |
| Language            | Python            | Ruby             |
| LLM extraction      | ✅                | Planned          |
| Markdown extraction | ✅                | ✅               |
| Link extraction     | ✅                | ✅               |
| Multi-page crawling | ✅                | ✅               |
| Rails integration   | N/A               | ✅               |
| Resource blocking   | ✅                | ✅               |
| Session management  | ✅                | Planned          |

RubyCrawl aims to bring the same level of accuracy and reliability to the Ruby ecosystem.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Credits

Inspired by [crawl4ai](https://github.com/unclecode/crawl4ai) by @unclecode.

Built with [Playwright](https://playwright.dev/) by Microsoft.

## Support

- **Issues**: [GitHub Issues](https://github.com/craft-wise/rubycrawl/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/rubycrawl/discussions)
- **Email**: ganesh.navale@zohomail.in
