# RubyCrawl 🎭

[![Gem Version](https://badge.fury.io/rb/rubycrawl.svg)](https://badge.fury.io/rb/rubycrawl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red.svg)](https://www.ruby-lang.org/)
[![Node.js](https://img.shields.io/badge/node.js-18%2B-green.svg)](https://nodejs.org/)

**Production-ready web crawler for Ruby powered by Playwright** — Bringing the power of modern browser automation to the Ruby ecosystem with first-class Rails support.

RubyCrawl provides **accurate, JavaScript-enabled web scraping** using Playwright's battle-tested browser automation, wrapped in a clean Ruby API. Perfect for extracting content from modern SPAs, dynamic websites, and building RAG knowledge bases.

**Why RubyCrawl?**

- ✅ **Real browser** — Handles JavaScript, AJAX, and SPAs correctly
- ✅ **Zero config** — Works out of the box, no Playwright knowledge needed
- ✅ **Production-ready** — Auto-retry, error handling, resource optimization
- ✅ **Multi-page crawling** — BFS algorithm with smart URL deduplication
- ✅ **Rails-friendly** — Generators, initializers, and ActiveJob integration
- ✅ **Modular architecture** — Clean, testable, maintainable codebase

## Features

- **🎭 Playwright-powered**: Real browser automation for JavaScript-heavy sites and SPAs
- **🚀 Production-ready**: Designed for Rails apps and production environments with auto-retry and error handling
- **🎯 Simple API**: Clean, minimal Ruby interface — zero Playwright or Node.js knowledge required
- **⚡ Resource optimization**: Built-in resource blocking for 2-3x faster crawls
- **🔄 Auto-managed browsers**: Browser process reuse and automatic lifecycle management
- **📄 Content extraction**: HTML, links (with metadata), and lazy-loaded Markdown conversion
- **🌐 Multi-page crawling**: BFS (breadth-first search) crawler with configurable depth limits and URL deduplication
- **🛡️ Smart URL handling**: Automatic normalization, tracking parameter removal, and same-host filtering
- **🔧 Rails integration**: First-class Rails support with generators and initializers
- **💎 Modular design**: Clean separation of concerns with focused, testable modules

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Use Cases](#use-cases)
- [Usage](#usage)
  - [Basic Crawling](#basic-crawling)
  - [Multi-Page Crawling](#multi-page-crawling)
  - [Configuration](#configuration)
  - [Result Object](#result-object)
  - [Error Handling](#error-handling)
- [Rails Integration](#rails-integration)
- [Production Deployment](#production-deployment)
- [Architecture](#architecture)
- [Performance](#performance)
- [Development](#development)
  - [Project Structure](#project-structure)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Why Choose RubyCrawl?](#why-choose-rubycrawl)
- [License](#license)
- [Support](#support)

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

- ✅ Installs Node.js dependencies in the bundled `node/` directory
- ✅ Downloads Playwright browsers (Chromium, Firefox, WebKit) — ~300MB download
- ✅ Creates a Rails initializer (if using Rails)

**Note:** You only need to run this once. The installation task is idempotent and safe to run multiple times.

**Troubleshooting installation:**

```bash
# If installation fails, check Node.js version
node --version  # Should be v18+ LTS

# Enable verbose logging
RUBYCRAWL_NODE_LOG=/tmp/rubycrawl.log bundle exec rake rubycrawl:install

# Check installation status
cd node && npm list
```

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

## Use Cases

RubyCrawl is perfect for:

- **📊 Data aggregation**: Crawl product catalogs, job listings, or news articles
- **🤖 RAG applications**: Build knowledge bases for LLM/AI applications by crawling documentation sites
- **🔍 SEO analysis**: Extract metadata, links, and content structure
- **📱 Content migration**: Convert existing sites to Markdown for static site generators
- **🧪 Testing**: Verify deployed site structure and content
- **📚 Documentation scraping**: Create local copies of documentation with preserved links

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

**Real-world example: Building a RAG knowledge base**

```ruby
# Crawl documentation site for AI/RAG application
require "rubycrawl"

RubyCrawl.configure(
  wait_until: "networkidle",  # Ensure JS content loads
  block_resources: true       # Skip images/fonts for speed
)

pages_crawled = RubyCrawl.crawl_site(
  "https://docs.example.com",
  max_pages: 500,
  max_depth: 5,
  same_host_only: true
) do |page|
  # Store in vector database for RAG
  VectorDB.upsert(
    id: Digest::SHA256.hexdigest(page.url),
    content: page.markdown,  # Clean markdown for better embeddings
    metadata: {
      url: page.url,
      title: page.metadata["title"],
      depth: page.depth
    }
  )

  puts "✓ Indexed: #{page.metadata['title']} (#{page.depth} levels deep)"
end

puts "Crawled #{pages_crawled} pages into knowledge base"
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

Links are extracted with full metadata:

```ruby
result.links
# => [
#   {
#     "url" => "https://example.com/about",
#     "text" => "About Us",
#     "title" => "Learn more about us",  # <a title="...">
#     "rel" => nil                        # <a rel="nofollow">
#   },
#   {
#     "url" => "https://example.com/contact",
#     "text" => "Contact",
#     "title" => null,
#     "rel" => "nofollow"
#   },
#   ...
# ]
```

**Note:** URLs are automatically converted to absolute URLs by the browser, so relative links like `/about` become `https://example.com/about`.

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

RubyCrawl uses a **dual-process architecture** with a modular Ruby design:

```
┌─────────────────────────────────────────────┐
│  Ruby Process (Your Application)            │
│  ┌─────────────────────────────────────┐   │
│  │  RubyCrawl Gem (Modular Design)      │   │
│  │  ┌─────────────────────────────┐    │   │
│  │  │ Public API (rubycrawl.rb)   │    │   │
│  │  └──────────┬──────────────────┘    │   │
│  │             │                        │   │
│  │  ┌──────────┴───────────────────┐   │   │
│  │  │ Core Modules:                │   │   │
│  │  │ • ServiceClient (Node mgmt)  │   │   │
│  │  │ • Result (lazy markdown)     │   │   │
│  │  │ • SiteCrawler (BFS)          │   │   │
│  │  │ • UrlNormalizer (dedup)      │   │   │
│  │  │ • MarkdownConverter (HTML→MD)│   │   │
│  │  │ • Helpers (validation)       │   │   │
│  │  │ • Errors (hierarchy)         │   │   │
│  │  └──────────────────────────────┘   │   │
│  └────────────┬────────────────────────┘   │
└───────────────┼─────────────────────────────┘
                │ HTTP/JSON (localhost:3344)
┌───────────────┼─────────────────────────────┐
│  Node.js Process (Auto-started by Ruby)     │
│  ┌────────────┴────────────────────────┐   │
│  │  Playwright Service (index.js)       │   │
│  │  • Browser lifecycle management      │   │
│  │  • Page navigation & waiting         │   │
│  │  • HTML extraction                   │   │
│  │  • Link extraction                   │   │
│  │  • Metadata extraction               │   │
│  │  • Resource blocking (performance)   │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Why this architecture?**

- **Separation of concerns**: Ruby handles orchestration, Node handles browsers
- **Modular design**: Focused modules for validation, HTTP, crawling, conversion
- **Stability**: Playwright's official Node.js bindings are most reliable
- **Performance**: Long-running browser process reused across requests
- **Lazy loading**: Markdown conversion only happens when accessed
- **Simplicity**: No C extensions, pure Ruby + bundled Node service

**Data Flow:**

1. **User calls** `RubyCrawl.crawl(url)` or `RubyCrawl.crawl_site(url)`
2. **ServiceClient** ensures Node service is running (auto-starts if needed)
3. **Helpers** validate URL and build request payload
4. **ServiceClient** sends HTTP POST to Node service
5. **Node service** uses Playwright to crawl page, extract HTML, links, metadata
6. **Result object** receives data, caches it, lazily converts markdown when accessed
7. **SiteCrawler** (if multi-page) normalizes URLs, deduplicates, follows links via BFS

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
│   ├── rubycrawl.rb                  # Main gem, public API
│   └── rubycrawl/
│       ├── version.rb                # Gem version
│       ├── errors.rb                 # Custom exception hierarchy
│       ├── helpers.rb                # URL validation, payload building
│       ├── service_client.rb         # Node service lifecycle & HTTP
│       ├── url_normalizer.rb         # URL normalization & deduplication
│       ├── markdown_converter.rb     # HTML → Markdown conversion
│       ├── result.rb                 # Result object with lazy markdown
│       ├── site_crawler.rb           # BFS multi-page crawler
│       ├── railtie.rb                # Rails integration
│       └── tasks/
│           └── install.rake          # Installation task
├── node/
│   ├── src/
│   │   └── index.js                  # Playwright HTTP service
│   ├── package.json                  # Node.js dependencies
│   └── README.md                     # Node service documentation
├── spec/
│   ├── rubycrawl_spec.rb             # RSpec tests
│   └── spec_helper.rb
├── .github/
│   └── copilot-instructions.md       # Contributor guidelines
├── CLAUDE.md                         # AI assistant guidelines
├── README.md                         # This file
├── rubycrawl.gemspec                 # Gem specification
└── Rakefile                          # Rake tasks
```

### Module Descriptions

**Core Modules:**

- **errors.rb** — Custom exception hierarchy (Error, ServiceError, NavigationError, TimeoutError, ConfigurationError)
- **helpers.rb** — URL validation, request payload building, error class mapping
- **service_client.rb** — Node.js service lifecycle management, health checks, HTTP communication
- **result.rb** — Result object with lazy markdown conversion and URL resolution
- **url_normalizer.rb** — URL normalization, deduplication, tracking parameter removal
- **markdown_converter.rb** — HTML to Markdown conversion using reverse_markdown gem
- **site_crawler.rb** — Breadth-first search multi-page crawler with depth limits

## Roadmap

### ✅ Current (v0.1.0)

**Completed Features:**

- [x] HTML extraction via Playwright
- [x] Link extraction with metadata (url, text, title, rel)
- [x] Markdown conversion (lazy-loaded with reverse_markdown)
- [x] Multi-page crawling with BFS algorithm
- [x] URL normalization and deduplication
- [x] Tracking parameter removal (utm_*, fbclid, etc.)
- [x] Comprehensive metadata extraction (OG tags, Twitter cards, etc.)
- [x] Custom exception hierarchy
- [x] Automatic retry with exponential backoff
- [x] Resource blocking for performance
- [x] Rails integration with generators
- [x] Modular, maintainable architecture

### 🔜 Coming Soon (v0.2.0)

**Planned Features:**

- [ ] Plain text extraction (DOM innerText)
- [ ] Screenshot capture (full page, element)
- [ ] Rate limiting for multi-page crawls
- [ ] Robots.txt support
- [ ] Custom user agents
- [ ] Configurable request headers

### 🚀 Future (v0.3.0+)

**Advanced Features:**

- [ ] Interactive crawling (click, scroll, fill forms)
- [ ] Session/cookie support
- [ ] Custom JavaScript execution
- [ ] Proxy support
- [ ] Authentication helpers
- [ ] Structured data extraction (JSON-LD, microdata)

### 💎 Long-term (v1.0.0)

**Maturity Goals:**

- [ ] Production battle-tested (1000+ stars, real-world usage)
- [ ] Full documentation with video tutorials
- [ ] Performance benchmarks vs. alternatives
- [ ] Migration guides from Nokogiri, Mechanize, etc.

## Contributing

Contributions are welcome! Please read our [contribution guidelines](.github/copilot-instructions.md) first.

### Development Philosophy

- **Simplicity over cleverness**: Prefer clear, explicit code
- **Stability over speed**: Correctness first, optimization second
- **Ruby-first**: Hide Node.js/Playwright complexity from users
- **No vendor lock-in**: Pure open source, no SaaS dependencies

## Why Choose RubyCrawl?

RubyCrawl stands out in the Ruby ecosystem with its unique combination of features:

### 🎯 **Built for Ruby Developers**
- **Idiomatic Ruby API** — Feels natural to Rubyists, no need to learn Playwright
- **Rails-first design** — Generators, initializers, and ActiveJob integration out of the box
- **Modular architecture** — Clean, testable code following Ruby best practices

### 🚀 **Production-Grade Reliability**
- **Automatic retry** with exponential backoff for transient failures
- **Smart error handling** with custom exception hierarchy
- **Process isolation** — Browser crashes don't affect your Ruby application
- **Battle-tested** — Built on Playwright's proven browser automation

### 💎 **Developer Experience**
- **Zero configuration** — Works immediately after installation
- **Lazy loading** — Markdown conversion only when you need it
- **Smart URL handling** — Automatic normalization and deduplication
- **Comprehensive docs** — Clear examples for common use cases

### 🌐 **Rich Feature Set**
- ✅ JavaScript-enabled crawling (SPAs, AJAX, dynamic content)
- ✅ Multi-page crawling with BFS algorithm
- ✅ Link extraction with metadata (url, text, title, rel)
- ✅ Markdown conversion (GitHub-flavored)
- ✅ Metadata extraction (OG tags, Twitter cards, etc.)
- ✅ Resource blocking for 2-3x performance boost

### 📊 **Perfect for Modern Use Cases**
- **RAG applications** — Build AI knowledge bases from documentation
- **Data aggregation** — Extract structured data from multiple pages
- **Content migration** — Convert sites to Markdown for static generators
- **SEO analysis** — Extract metadata and link structures
- **Testing** — Verify deployed site content and structure

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Credits

Built with [Playwright](https://playwright.dev/) by Microsoft — the industry-standard browser automation framework.

Powered by [reverse_markdown](https://github.com/xijo/reverse_markdown) for GitHub-flavored Markdown conversion.

## Support

- **Issues**: [GitHub Issues](https://github.com/craft-wise/rubycrawl/issues)
- **Discussions**: [GitHub Discussions](https://github.com/craft-wise/rubycrawl/discussions)
- **Email**: ganesh.navale@zohomail.in

## Acknowledgments

Special thanks to:
- [Microsoft Playwright](https://playwright.dev/) team for the robust, production-grade browser automation framework
- The Ruby community for building an ecosystem that values developer happiness and code clarity
- The Node.js community for excellent tooling and libraries that make cross-language integration seamless
- Open source contributors worldwide who make projects like this possible
