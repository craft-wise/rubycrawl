# RubyCrawl 🎭

[![Gem Version](https://badge.fury.io/rb/rubycrawl.svg)](https://rubygems.org/gems/rubycrawl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red.svg)](https://www.ruby-lang.org/)

**Production-ready web crawler for Ruby powered by Ferrum** — Full JavaScript rendering via Chrome DevTools Protocol, with first-class Rails support and no Node.js dependency.

RubyCrawl provides **accurate, JavaScript-enabled web scraping** using a pure Ruby browser automation stack. Perfect for extracting content from modern SPAs, dynamic websites, and building RAG knowledge bases.

**Why RubyCrawl?**

- ✅ **Real browser** — Handles JavaScript, AJAX, and SPAs correctly
- ✅ **Pure Ruby** — No Node.js, no npm, no external processes to manage
- ✅ **Zero config** — Works out of the box, no Ferrum knowledge needed
- ✅ **Production-ready** — Auto-retry, error handling, resource optimization
- ✅ **Multi-page crawling** — BFS algorithm with smart URL deduplication
- ✅ **Rails-friendly** — Generators, initializers, and ActiveJob integration

```ruby
# One line to crawl any JavaScript-heavy site
result = RubyCrawl.crawl("https://docs.example.com")

result.html           # Full HTML with JS rendered
result.clean_text     # Noise-stripped plain text (no nav/footer/ads)
result.clean_markdown # Markdown ready for RAG pipelines
result.links          # All links with url, text, title, rel
result.metadata       # Title, description, OG tags, etc.
```

## Features

- **Pure Ruby**: Ferrum drives Chromium directly via CDP — no Node.js or npm required
- **Production-ready**: Designed for Rails apps with auto-retry and exponential backoff
- **Simple API**: Clean Ruby interface — zero Ferrum or CDP knowledge required
- **Resource optimization**: Built-in resource blocking for 2-3x faster crawls
- **Auto-managed browsers**: Lazy Chrome singleton, isolated page per crawl
- **Content extraction**: HTML, plain text, clean HTML, Markdown (lazy), links, metadata
- **Multi-page crawling**: BFS crawler with configurable depth limits and URL deduplication
- **Smart URL handling**: Automatic normalization, tracking parameter removal, same-host filtering
- **Rails integration**: First-class Rails support with generators and initializers

## Table of Contents

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
- [Contributing](#contributing)
- [License](#license)

## Installation

### Requirements

- **Ruby** >= 3.0
- **Chrome or Chromium** — managed automatically by Ferrum (downloaded on first use)

### Add to Gemfile

```ruby
gem "rubycrawl"
```

Then install:

```bash
bundle install
```

### Install Chrome

Ferrum manages Chrome automatically. Run the install task to verify Chrome is available and generate a Rails initializer:

```bash
bundle exec rake rubycrawl:install
```

This command:

- ✅ Checks for Chrome/Chromium in your PATH
- ✅ Creates a Rails initializer (if using Rails)

**Note:** If Chrome is not in your PATH, install it via your system package manager or download from [google.com/chrome](https://www.google.com/chrome/).

## Quick Start

```ruby
require "rubycrawl"

# Simple crawl
result = RubyCrawl.crawl("https://example.com")

# Access extracted content
result.final_url      # Final URL after redirects
result.clean_text     # Noise-stripped plain text (no nav/footer/ads)
result.clean_html     # Noise-stripped HTML (same noise removed as clean_text)
result.raw_text       # Full body.innerText (unfiltered)
result.html           # Full raw HTML content
result.links          # Extracted links with url, text, title, rel
result.metadata       # Title, description, OG tags, etc.
result.clean_markdown # Markdown converted from clean_html (lazy — first access only)
```

## Use Cases

RubyCrawl is perfect for:

- **RAG applications**: Build knowledge bases for LLM/AI applications by crawling documentation sites
- **Data aggregation**: Crawl product catalogs, job listings, or news articles
- **SEO analysis**: Extract metadata, links, and content structure
- **Content migration**: Convert existing sites to Markdown for static site generators
- **Documentation scraping**: Create local copies of documentation with preserved links

## Usage

### Basic Crawling

```ruby
result = RubyCrawl.crawl("https://example.com")

result.html           # => "<html>...</html>"
result.clean_text     # => "Example Domain\n\nThis domain is..." (no nav/ads)
result.raw_text       # => "Example Domain\nThis domain is..." (full body text)
result.metadata       # => { "final_url" => "https://example.com", "title" => "..." }
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
    url:      page.url,
    html:     page.html,
    markdown: page.clean_markdown,
    depth:    page.depth
  )
end
```

**Real-world example: Building a RAG knowledge base**

```ruby
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
  VectorDB.upsert(
    id:       Digest::SHA256.hexdigest(page.url),
    content:  page.clean_markdown,
    metadata: {
      url:   page.url,
      title: page.metadata["title"],
      depth: page.depth
    }
  )
end

puts "Indexed #{pages_crawled} pages"
```

#### Multi-Page Options

| Option            | Default   | Description                          |
| ----------------- | --------- | ------------------------------------ |
| `max_pages`       | 50        | Maximum number of pages to crawl     |
| `max_depth`       | 3         | Maximum link depth from start URL    |
| `same_host_only`  | true      | Only follow links on the same domain |
| `wait_until`      | inherited | Page load strategy                   |
| `block_resources` | inherited | Block images/fonts/CSS               |

#### Page Result Object

The block receives a `PageResult` with:

```ruby
page.url            # String: Final URL after redirects
page.html           # String: Full raw HTML content
page.clean_html     # String: Noise-stripped HTML (no nav/header/footer/ads)
page.clean_text     # String: Noise-stripped plain text (derived from clean_html)
page.raw_text       # String: Full body.innerText (unfiltered)
page.clean_markdown # String: Lazy-converted Markdown from clean_html
page.links          # Array: URLs extracted from page
page.metadata       # Hash: final_url, title, OG tags, etc.
page.depth          # Integer: Link depth from start URL
```

### Configuration

#### Global Configuration

```ruby
RubyCrawl.configure(
  wait_until:      "networkidle",
  block_resources: true,
  timeout:         60,
  headless:        true
)

# All subsequent crawls use these defaults
result = RubyCrawl.crawl("https://example.com")
```

#### Per-Request Options

```ruby
# Use global defaults
result = RubyCrawl.crawl("https://example.com")

# Override for this request only
result = RubyCrawl.crawl(
  "https://example.com",
  wait_until:      "domcontentloaded",
  block_resources: false
)
```

#### Configuration Options

| Option            | Values                                                      | Default | Description                                         |
| ----------------- | ----------------------------------------------------------- | ------- | --------------------------------------------------- |
| `wait_until`      | `"load"`, `"domcontentloaded"`, `"networkidle"`, `"commit"` | `nil`   | When to consider page loaded (nil = Ferrum default) |
| `block_resources` | `true`, `false`                                             | `nil`   | Block images, fonts, CSS, media for faster crawls   |
| `max_attempts`    | Integer                                                     | `3`     | Total number of attempts (including the first)      |
| `timeout`         | Integer (seconds)                                           | `30`    | Browser navigation timeout                          |
| `headless`        | `true`, `false`                                             | `true`  | Run Chrome headlessly                               |

**Wait strategies explained:**

- `load` — Wait for the load event (good for static sites)
- `domcontentloaded` — Wait for DOM ready (faster)
- `networkidle` — Wait until no network requests for 500ms (best for SPAs)
- `commit` — Wait until the first response bytes are received (fastest)

### Result Object

```ruby
result = RubyCrawl.crawl("https://example.com")

result.html           # String: Full raw HTML
result.clean_html     # String: Noise-stripped HTML (nav/header/footer/ads removed)
result.clean_text     # String: Plain text derived from clean_html — ideal for RAG
result.raw_text       # String: Full body.innerText (unfiltered)
result.clean_markdown # String: Markdown from clean_html (lazy — computed on first access)
result.links          # Array: Extracted links with url/text/title/rel
result.metadata       # Hash: See below
result.final_url      # String: Shortcut for metadata['final_url']
```

#### Links Format

```ruby
result.links
# => [
#   { "url" => "https://example.com/about", "text" => "About", "title" => nil, "rel" => nil },
#   { "url" => "https://example.com/contact", "text" => "Contact", "title" => nil, "rel" => "nofollow" },
# ]
```

URLs are automatically resolved to absolute form by the browser.

#### Markdown Conversion

Markdown is **lazy** — conversion only happens on first access of `.clean_markdown`:

```ruby
result.clean_html     # ✅ Already available, no overhead
result.clean_markdown # Converts clean_html → Markdown here (first call only)
result.clean_markdown # ✅ Cached, instant on subsequent calls
```

Uses [reverse_markdown](https://github.com/xijo/reverse_markdown) with GitHub-flavored output.

#### Metadata Fields

```ruby
result.metadata
# => {
#   "final_url"           => "https://example.com",
#   "title"               => "Page Title",
#   "description"         => "...",
#   "keywords"            => "ruby, web",
#   "author"              => "Author Name",
#   "og_title"            => "...",
#   "og_description"      => "...",
#   "og_image"            => "https://...",
#   "og_url"              => "https://...",
#   "og_type"             => "website",
#   "twitter_card"        => "summary",
#   "twitter_title"       => "...",
#   "twitter_description" => "...",
#   "twitter_image"       => "https://...",
#   "canonical"           => "https://...",
#   "lang"                => "en",
#   "charset"             => "UTF-8"
# }
```

### Error Handling

```ruby
begin
  result = RubyCrawl.crawl(url)
rescue RubyCrawl::ConfigurationError => e
  # Invalid URL or option value
rescue RubyCrawl::TimeoutError => e
  # Page load timed out
rescue RubyCrawl::NavigationError => e
  # Navigation failed (404, DNS error, SSL error)
rescue RubyCrawl::ServiceError => e
  # Browser failed to start or crashed
rescue RubyCrawl::Error => e
  # Catch-all for any RubyCrawl error
end
```

**Exception Hierarchy:**

```
RubyCrawl::Error
  ├── ConfigurationError  — invalid URL or option value
  ├── TimeoutError        — page load timed out
  ├── NavigationError     — navigation failed (HTTP error, DNS, SSL)
  └── ServiceError        — browser failed to start or crashed
```

**Automatic Retry:** `ServiceError` and `TimeoutError` are retried with exponential backoff. `NavigationError` and `ConfigurationError` are not retried (they won't succeed on retry).

```ruby
RubyCrawl.configure(max_attempts: 5)     # 5 total attempts
RubyCrawl.crawl(url, max_attempts: 1)    # Disable retries
```

## Rails Integration

### Installation

```bash
bundle exec rake rubycrawl:install
```

This creates `config/initializers/rubycrawl.rb`:

```ruby
RubyCrawl.configure(
  wait_until:      "load",
  block_resources: true
)
```

### Usage in Rails

#### Background Jobs with ActiveJob

```ruby
class CrawlPageJob < ApplicationJob
  queue_as :crawlers

  retry_on RubyCrawl::ServiceError, wait: :exponentially_longer, attempts: 5
  retry_on RubyCrawl::TimeoutError, wait: :exponentially_longer, attempts: 3
  discard_on RubyCrawl::ConfigurationError

  def perform(url)
    result = RubyCrawl.crawl(url)

    Page.create!(
      url:        result.final_url,
      title:      result.metadata['title'],
      content:    result.clean_text,
      markdown:   result.clean_markdown,
      crawled_at: Time.current
    )
  end
end
```

**Multi-page RAG knowledge base:**

```ruby
class BuildKnowledgeBaseJob < ApplicationJob
  queue_as :crawlers

  def perform(documentation_url)
    RubyCrawl.crawl_site(documentation_url, max_pages: 500, max_depth: 5) do |page|
      embedding = OpenAI.embed(page.clean_markdown)

      Document.create!(
        url:       page.url,
        title:     page.metadata['title'],
        content:   page.clean_markdown,
        embedding: embedding,
        depth:     page.depth
      )
    end
  end
end
```

#### Best Practices

1. **Use background jobs** to avoid blocking web requests
2. **Configure retry logic** based on error type
3. **Store `clean_markdown`** for RAG applications (preserves heading structure for chunking)
4. **Rate limit** external crawling to be respectful

## Production Deployment

### Pre-deployment Checklist

1. **Ensure Chrome is installed** on your production servers
2. **Run installer** during deployment:
   ```bash
   bundle exec rake rubycrawl:install
   ```

### Docker Example

```dockerfile
FROM ruby:3.2

# Install Chrome
RUN apt-get update && apt-get install -y \
    chromium \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile* ./
RUN bundle install

COPY . .
CMD ["rails", "server"]
```

Ferrum will detect `chromium` automatically. To specify a custom path:

```ruby
RubyCrawl.configure(
  browser_options: { "browser-path": "/usr/bin/chromium" }
)
```

## Architecture

RubyCrawl uses a single-process architecture:

```
RubyCrawl (public API)
  ↓
Browser (lib/rubycrawl/browser.rb)  ← Ferrum wrapper
  ↓
Ferrum::Browser                     ← Chrome DevTools Protocol (pure Ruby)
  ↓
Chromium                            ← headless browser
```

- Chrome launches once lazily and is reused across all crawls
- Each crawl gets an isolated page context (own cookies/storage)
- JS extraction runs inside the browser via `page.evaluate()`
- No separate processes, no HTTP boundary, no Node.js

## Performance

- **Resource blocking**: Keep `block_resources: true` (default: nil) to skip images/fonts/CSS for 2-3x faster crawls
- **Wait strategy**: Use `wait_until: "load"` for static sites, `"networkidle"` for SPAs
- **Concurrency**: Use background jobs (Sidekiq, GoodJob, etc.) for parallel crawling
- **Browser reuse**: The first crawl is slower (~2s) due to Chrome launch; subsequent crawls are much faster (~200-500ms)

## Development

```bash
git clone git@github.com:craft-wise/rubycrawl.git
cd rubycrawl
bin/setup

# Run unit tests (no browser required)
bundle exec rspec

# Run integration tests (requires Chrome)
INTEGRATION=1 bundle exec rspec

# Manual testing
bin/console
> RubyCrawl.crawl("https://example.com")
> RubyCrawl.crawl("https://example.com").clean_text
> RubyCrawl.crawl("https://example.com").clean_markdown
```

## Contributing

Contributions are welcome! Please read our [contribution guidelines](.github/copilot-instructions.md) first.

- **Simplicity over cleverness**: Prefer clear, explicit code
- **Stability over speed**: Correctness first, optimization second
- **Hide complexity**: Users should never need to know Ferrum exists

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Credits

Built with [Ferrum](https://github.com/rubycdp/ferrum) — pure Ruby Chrome DevTools Protocol client.

Powered by [reverse_markdown](https://github.com/xijo/reverse_markdown) for GitHub-flavored Markdown conversion.

## Support

- **Issues**: [GitHub Issues](https://github.com/craft-wise/rubycrawl/issues)
- **Discussions**: [GitHub Discussions](https://github.com/craft-wise/rubycrawl/discussions)
- **Email**: ganesh.navale@zohomail.in
