# frozen_string_literal: true

require 'spec_helper'
require 'base64'

# Article with enough prose for Readability to identify main content.
ARTICLE_HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <title>How Ruby Changed Programming</title>
    <meta name="description" content="A deep dive into Ruby's history and philosophy.">
  </head>
  <body>
    <nav><a href="/home">Home</a> <a href="/blog">Blog</a> <a href="/about">About</a></nav>
    <main>
      <article>
        <h1>How Ruby Changed Programming</h1>
        <p>Ruby is a dynamic, open source programming language with a focus on simplicity
        and productivity. It has an elegant syntax that is natural to read and easy to write.</p>
        <p>Created by Yukihiro Matsumoto in the mid-1990s, Ruby was designed with the principle
        of least astonishment. Matz designed Ruby to minimise frustration and maximise joy.</p>
        <p>The language gained widespread adoption through the Ruby on Rails framework, which
        revolutionised web development with convention over configuration and DRY principles.</p>
        <p>Today Ruby continues to evolve with regular releases that improve performance and
        add new features. The community remains vibrant and welcoming to all developers.</p>
        <h2>Metaprogramming</h2>
        <p>Metaprogramming allows code to write code at runtime, enabling domain-specific
        languages and flexible APIs that feel completely natural to use every day.</p>
      </article>
    </main>
    <footer><p>Copyright 2024. All rights reserved.</p></footer>
  </body>
  </html>
HTML

# Page whose article content is below our 200-char threshold, so Readability's
# result is discarded and the heuristic fallback runs instead.
SPARSE_HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
  <head><title>Site Index</title></head>
  <body>
    <article><p>Brief.</p></article>
    <nav>
      <a href="/alpha">Alpha</a> <a href="/beta">Beta</a> <a href="/gamma">Gamma</a>
      <a href="/delta">Delta</a> <a href="/epsilon">Epsilon</a> <a href="/zeta">Zeta</a>
      <a href="/eta">Eta</a> <a href="/theta">Theta</a> <a href="/iota">Iota</a>
    </nav>
  </body>
  </html>
HTML

# Integration tests for RubyCrawl::Browser.
#
# Uses data: URLs so Chrome loads HTML directly from memory — no network
# calls, no WEBrick server, works offline and on CI (Chrome required).
#
# Run with: INTEGRATION=1 bundle exec rspec spec/browser_integration_spec.rb
RSpec.describe RubyCrawl::Browser, :integration do
  # One Chrome instance shared across all examples — launch is slow (~2s).
  before(:context) { @browser = described_class.new(headless: true, timeout: 30) }

  # Encode HTML as a data: URL so Ferrum can navigate to it without HTTP.
  def data_url(html)
    "data:text/html;base64,#{Base64.strict_encode64(html)}"
  end

  # ── Extractor selection ──────────────────────────────────────────────────────

  describe 'extractor selection' do
    it 'uses Readability for article pages' do
      result = @browser.crawl(data_url(ARTICLE_HTML))
      expect(result.metadata['extractor']).to eq('readability')
    end

    it 'falls back to heuristic when Readability content is below threshold' do
      result = @browser.crawl(data_url(SPARSE_HTML))
      expect(result.metadata['extractor']).to eq('heuristic')
    end
  end

  # ── Article page — content quality ──────────────────────────────────────────

  describe 'article page extraction' do
    subject(:result) { @browser.crawl(data_url(ARTICLE_HTML)) }

    it 'clean_html contains article body content' do
      # Readability moves <h1> to article.title — check paragraph text instead
      expect(result.clean_html).to include('least astonishment')
      expect(result.clean_html).to include('Metaprogramming')
    end

    it 'clean_html excludes nav and footer' do
      expect(result.clean_html).not_to match(/<nav[\s>]/)
      expect(result.clean_html).not_to match(/<footer[\s>]/)
    end

    it 'clean_text has no HTML tags' do
      expect(result.clean_text).to include('least astonishment')
      expect(result.clean_text).not_to include('<')
    end

    it 'clean_markdown preserves heading structure' do
      # Readability moves <h1> to article.title — h2 stays in content
      expect(result.clean_markdown).to include('## Metaprogramming')
      expect(result.clean_markdown).to include('least astonishment')
    end

    it 'clean_markdown is lazy — not computed until accessed' do
      fresh = @browser.crawl(data_url(ARTICLE_HTML))
      expect(fresh.clean_markdown?).to be false
      fresh.clean_markdown
      expect(fresh.clean_markdown?).to be true
    end
  end

  # ── Sparse page — heuristic fallback ────────────────────────────────────────

  describe 'sparse page extraction (heuristic fallback)' do
    subject(:result) { @browser.crawl(data_url(SPARSE_HTML)) }

    it 'clean_html is not empty' do
      expect(result.clean_html).not_to be_empty
    end

    it 'extracts links' do
      expect(result.links.size).to be >= 9
    end

    it 'extracts title from metadata' do
      expect(result.metadata['title']).to eq('Site Index')
    end
  end

  # ── Result fields — populated for any page ──────────────────────────────────

  describe 'result fields' do
    subject(:result) { @browser.crawl(data_url(ARTICLE_HTML)) }

    it 'html contains the full document including nav and footer' do
      expect(result.html).to include('<nav>')
      expect(result.html).to include('<footer>')
    end

    it 'raw_text is the unfiltered body text' do
      expect(result.raw_text).to include('How Ruby Changed Programming')
      expect(result.raw_text).to include('Home') # nav text present in raw
    end

    it 'links are extracted with url and text' do
      expect(result.links).not_to be_empty
      blog_link = result.links.find { |l| l['url'].end_with?('/blog') }
      expect(blog_link).not_to be_nil
      expect(blog_link['text']).to eq('Blog')
    end

    it 'metadata includes title, description, lang, and extractor' do
      expect(result.metadata['title']).to eq('How Ruby Changed Programming')
      expect(result.metadata['description']).to eq("A deep dive into Ruby's history and philosophy.")
      expect(result.metadata['lang']).to eq('en')
      expect(%w[readability heuristic]).to include(result.metadata['extractor'])
    end

    it 'final_url is populated' do
      expect(result.final_url).not_to be_nil
    end
  end
end
