# Claude Code Instructions for rubycrawl

## Project Overview

**rubycrawl** is an open-source, production-ready web crawler for Ruby that uses Playwright for browser automation. It's inspired by [crawl4ai](https://github.com/unclecode/crawl4ai) (Python) but designed idiomatically for Ruby with first-class Rails support.

### Key Characteristics

- **Dual-process architecture**: Ruby (orchestration) + Node.js (browser automation)
- **Production-focused**: Built for stability, observability, and real-world deployment
- **Developer-friendly**: Simple API that hides Playwright complexity
- **Open source**: MIT licensed, no vendor lock-in, no SaaS components

## Architecture at a Glance

```
Ruby Gem (lib/rubycrawl.rb)
  ↓ HTTP/JSON (localhost:3344)
Node Service (node/src/index.js)
  ↓ Playwright API
Chromium Browser (managed by Playwright)
```

**Why this architecture?**
- Stability: Playwright's Node.js bindings are most mature
- Isolation: Browser crashes don't kill Ruby process
- Simplicity: HTTP is easy to debug and understand

## When Working on This Project

### Understanding the Codebase

1. **Start with the public API** ([lib/rubycrawl.rb](lib/rubycrawl.rb)):
   - `RubyCrawl.crawl(url, **options)` — main entry point
   - `RubyCrawl.configure(**defaults)` — global config
   - `RubyCrawl::Result` — return value struct

2. **Then examine the Node service** ([node/src/index.js](node/src/index.js)):
   - `/crawl` endpoint — does the actual Playwright work
   - `/health` endpoint — health checks
   - Browser singleton pattern

3. **Check the Rails integration** ([lib/rubycrawl/railtie.rb](lib/rubycrawl/railtie.rb)):
   - Rake tasks for installation
   - Initializer generation

### Making Changes

#### Ruby Code Guidelines

- **Keep it simple**: Prefer explicit code over metaprogramming
- **Hide complexity**: Don't expose Playwright concepts to users
- **Return rich objects**: Use `Result` struct, not hashes
- **Handle errors gracefully**: Wrap Node errors in meaningful Ruby exceptions

Example of good error handling:
```ruby
if response.is_a?(Hash) && response["error"]
  raise RubyCrawl::CrawlError, "Crawl failed: #{response['message']}"
end
```

#### Node.js Code Guidelines

- **Stateless requests**: Each `/crawl` request is independent
- **Stateful process**: Browser lives across requests
- **Always cleanup**: Close pages in `finally` blocks
- **Return JSON only**: Never return HTML or plain text responses

Example of good resource management:
```javascript
const page = await context.newPage();
try {
  // Do work
  return json(res, 200, { ok: true, html: await page.content() });
} finally {
  await page.close();  // Always cleanup
}
```

#### Testing Expectations

- **Ruby tests**: Fast unit tests that mock Node responses
- **No browser tests in Ruby**: Don't test Playwright behavior
- **Test error paths**: Errors are first-class citizens

Example test structure:
```ruby
RSpec.describe RubyCrawl do
  describe ".crawl" do
    it "returns a Result with html content"
    it "raises error when Node service returns error"
    it "merges global config with request options"
  end
end
```

### Common Tasks

#### Adding a New Configuration Option

1. Add parameter to Ruby API:
   ```ruby
   def crawl(url, wait_until: @wait_until, new_option: @new_option)
     payload = { url: url }
     payload[:new_option] = new_option if new_option
     # ...
   end
   ```

2. Handle in Node service:
   ```javascript
   const newOption = body.new_option || DEFAULT_VALUE;
   // Use the option
   ```

3. Document in README and copilot-instructions.md

4. Add tests for the new option

#### Adding Content Extraction Features

Currently, we only extract HTML. To add text/markdown/links:

1. **Implement in Node first** (faster iteration):
   ```javascript
   const text = await page.textContent('body');
   return json(res, 200, {
     ok: true,
     html: await page.content(),
     text: text,  // New field
     // ...
   });
   ```

2. **Update Ruby Result struct**:
   ```ruby
   Result.new(
     html: response["html"].to_s,
     text: response["text"].to_s,  # Now populated
     # ...
   )
   ```

3. **Update tests and docs**

#### Debugging Issues

**Node service not starting:**
- Check: Is Node.js installed? (`which node`)
- Check: Is Node service directory present?
- Check: Are npm dependencies installed?
- Look at: `ENV["RUBYCRAWL_NODE_LOG"]` if set

**Crawl timing out:**
- Check: Network connectivity to target URL
- Try: Increasing timeout in `page.goto()`
- Try: Different `wait_until` strategy
- Look at: Node service logs

**Memory issues:**
- Check: Are pages being closed after crawls?
- Check: Is context being cleaned up?
- Try: Restart Node service (future: add endpoint)

### Code Review Checklist

When reviewing or writing code:

- [ ] Public API is clean and Ruby-idiomatic?
- [ ] Playwright complexity is hidden from users?
- [ ] Errors include helpful context?
- [ ] Resources are cleaned up (pages, contexts)?
- [ ] Changes are backward compatible (or major bump)?
- [ ] README is updated if API changed?
- [ ] Tests cover new behavior?
- [ ] Logs include useful debugging info?

## Design Philosophy

### What We Value

1. **Correctness over Speed**: A slow but correct crawl beats a fast but wrong one
2. **Stability over Features**: Production reliability matters more than feature count
3. **Simplicity over Cleverness**: Code should be boring and maintainable
4. **Observability over Opacity**: Make failures easy to diagnose
5. **Contributor-Friendly**: Assume contributors know Ruby, not Node.js

### What We Avoid

- **Magic**: No DSLs, no metaprogramming unless it dramatically improves UX
- **Premature Optimization**: Profile first, optimize second
- **Feature Creep**: Keep scope focused on web crawling
- **Vendor Lock-in**: No proprietary dependencies or cloud services
- **Clever JavaScript**: Keep Node code simple and well-commented

## Current Status (v0.1.0)

### What Works

- ✅ HTML extraction
- ✅ Basic metadata (status code, final URL)
- ✅ Resource blocking for performance
- ✅ Auto-start Node service
- ✅ Rails integration and generators
- ✅ Health checks

### What's Coming (Roadmap)

**v0.2.0** (Next):
- Link extraction
- Plain text extraction
- Markdown conversion
- Screenshot capture

**v0.3.0** (Future):
- Interactive crawling (click, scroll, fill forms)
- Session/cookie support
- Custom JavaScript execution

**v0.4.0** (Future):
- Proxy support
- Custom headers
- Authentication helpers

**v1.0.0** (Stable):
- Production battle-tested
- Full documentation
- Performance benchmarks
- Migration guide from other crawlers

## Anti-Patterns to Avoid

### In Ruby Code

❌ **Don't** call Playwright directly:
```ruby
# Bad - creates tight coupling
browser = Playwright::Browser.new
page = browser.new_page
```

✅ **Do** use the Node service:
```ruby
# Good - uses our abstraction
result = RubyCrawl.crawl(url)
```

❌ **Don't** parse HTML in the gem (yet):
```ruby
# Bad - Ruby HTML parsing is for later
doc = Nokogiri::HTML(result.html)
```

✅ **Do** return raw HTML for now:
```ruby
# Good - users can parse as they wish
result.html  # Raw HTML string
```

### In Node Code

❌ **Don't** implement business logic:
```javascript
// Bad - this is user's responsibility
if (html.includes("product")) {
  return { type: "product_page" };
}
```

✅ **Do** extract raw data only:
```javascript
// Good - return raw HTML, let user interpret
return {
  html: await page.content(),
  metadata: { status: response.status() }
};
```

❌ **Don't** persist state across requests:
```javascript
// Bad - creates hidden state
const globalCache = {};
globalCache[url] = result;
```

✅ **Do** keep requests stateless:
```javascript
// Good - each request is independent
const page = await context.newPage();
try {
  // Process request
} finally {
  await page.close();  // Clean slate
}
```

## Working with Claude Code

### Effective Prompts

**Good prompts:**
- "Add link extraction to the crawl result"
- "Improve error messages when Node service fails to start"
- "Add configuration option for custom timeout"
- "Update README with Docker deployment example"

**Prompts that need clarification:**
- "Make it faster" → Ask: Which part? What's the current bottleneck?
- "Add authentication" → Ask: What type? OAuth, basic auth, cookies?
- "Fix the bug" → Ask: Which bug? What's the symptom?

### When to Ask Questions

Ask the user for clarification when:
- **Architecture changes**: "Should we extract links in Node or Ruby?"
- **Breaking changes**: "This would change the API. Bump to v1.0.0?"
- **Multiple approaches**: "Use Nokogiri or keep extraction in Node?"
- **Unclear requirements**: "What format for markdown conversion?"

### When to Be Proactive

Make decisions yourself when:
- **Code style**: Follow existing patterns
- **Error handling**: Add helpful error messages
- **Documentation**: Update docs for API changes
- **Testing**: Add tests for new features
- **Logging**: Add debug logs for observability

## File Structure Reference

```
rubycrawl/
├── lib/
│   ├── rubycrawl.rb              # Main gem, public API
│   ├── rubycrawl/
│   │   ├── version.rb           # Gem version (SemVer)
│   │   ├── railtie.rb           # Rails integration
│   │   └── tasks/
│   │       └── install.rake     # `rake rubycrawl:install`
├── node/
│   ├── src/
│   │   └── index.js             # HTTP service + Playwright
│   ├── package.json             # Node dependencies
│   └── README.md                # Node service docs
├── spec/
│   ├── rubycrawl_spec.rb         # RSpec tests
│   └── spec_helper.rb
├── .github/
│   └── copilot-instructions.md  # GitHub Copilot guide
├── CLAUDE.md                    # This file
├── README.md                    # User-facing documentation
├── rubycrawl.gemspec             # Gem specification
└── Rakefile                     # Rake tasks
```

## Quick Reference Commands

### Development

```bash
# Setup
bin/setup

# Run tests
bundle exec rspec

# Manual testing
bin/console
> RubyCrawl.crawl("https://example.com")
```

### Installation

```bash
# Install Playwright browsers
bundle exec rake rubycrawl:install

# Check Node service manually
cd node && npm start
```

### Debugging

```bash
# Enable Node service logs
export RUBYCRAWL_NODE_LOG=/tmp/rubycrawl.log

# Check if Node service is running
curl http://localhost:3344/health

# Manual crawl request
curl -X POST http://localhost:3344/crawl \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
```

## Getting Help

- **Architecture questions**: See [.github/copilot-instructions.md](.github/copilot-instructions.md)
- **Playwright docs**: https://playwright.dev/
- **Ruby style guide**: https://rubystyle.guide/
- **SemVer**: https://semver.org/

## Contributing

When contributing to rubycrawl:

1. **Read the copilot instructions**: Understand the architecture
2. **Start small**: Fix a bug or improve docs before adding features
3. **Ask questions**: Use GitHub Discussions for design questions
4. **Write tests**: All new code needs tests
5. **Update docs**: Keep README and comments in sync
6. **Follow conventions**: Match existing code style
7. **Be kind**: Assume positive intent, help others learn

---

**Remember**: We're building a tool that Ruby developers will rely on in production. Stability, clarity, and good documentation matter more than clever code or bleeding-edge features.
