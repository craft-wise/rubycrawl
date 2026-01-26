# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'spec_helper'

RSpec.describe RubyCrawl do
  describe '.crawl' do
    it 'returns a result object with HTML and metadata' do
      result = described_class.crawl('https://example.com')

      expect(result).to be_a(RubyCrawl::Result)
      expect(result.html).to be_a(String)
      expect(result.links).to be_a(Array)
      expect(result.metadata).to be_a(Hash)
      expect(result.metadata).to include('status', 'final_url')
    end

    it 'includes HTML metadata when available' do
      result = described_class.crawl('https://example.com')

      # Metadata keys that should be present (may be nil)
      expect(result.metadata.keys).to include('title', 'description', 'canonical')
    end
  end

  describe 'error handling' do
    it 'raises ConfigurationError for invalid URLs' do
      expect do
        described_class.crawl('not-a-url')
      end.to raise_error(RubyCrawl::ConfigurationError, /Invalid URL/)
    end

    it 'raises ConfigurationError for non-HTTP(S) URLs' do
      expect do
        described_class.crawl('ftp://example.com')
      end.to raise_error(RubyCrawl::ConfigurationError, /Only HTTP\(S\) URLs are supported/)
    end
  end

  describe 'custom exceptions' do
    it 'defines error hierarchy' do
      expect(RubyCrawl::Error).to be < StandardError
      expect(RubyCrawl::ServiceError).to be < RubyCrawl::Error
      expect(RubyCrawl::NavigationError).to be < RubyCrawl::Error
      expect(RubyCrawl::TimeoutError).to be < RubyCrawl::Error
      expect(RubyCrawl::ConfigurationError).to be < RubyCrawl::Error
    end
  end

  describe 'session management' do
    it 'creates and destroys sessions' do
      session_id = described_class.create_session

      expect(session_id).to be_a(String)
      expect(session_id).to start_with('sess_')

      # Should not raise error
      expect do
        described_class.destroy_session(session_id)
      end.not_to raise_error
    end

    it 'can reuse session across multiple crawls' do
      session_id = described_class.create_session

      begin
        result1 = described_class.crawl('https://example.com', session_id: session_id)
        result2 = described_class.crawl('https://example.com/about', session_id: session_id)

        expect(result1).to be_a(RubyCrawl::Result)
        expect(result2).to be_a(RubyCrawl::Result)
      ensure
        described_class.destroy_session(session_id)
      end
    end

    it 'handles destroy of non-existent session gracefully' do
      # Idempotent - destroying non-existent session should not raise
      expect do
        described_class.destroy_session('sess_nonexistent')
      end.not_to raise_error
    end
  end

  describe '.crawl_site' do
    it 'crawls multiple pages and yields results' do
      pages = []

      pages_crawled = described_class.crawl_site(
        'https://example.com',
        max_pages: 3,
        max_depth: 1
      ) do |page|
        pages << page
      end

      expect(pages_crawled).to be > 0
      expect(pages.length).to eq(pages_crawled)
      expect(pages.first).to be_a(RubyCrawl::SiteCrawler::PageResult)
      expect(pages.first.url).to be_a(String)
      expect(pages.first.html).to be_a(String)
      expect(pages.first.depth).to be_a(Integer)
    end

    it 'requires a block' do
      expect do
        described_class.crawl_site('https://example.com')
      end.to raise_error(ArgumentError, /Block required/)
    end
  end
end
# rubocop:enable Metrics/BlockLength
