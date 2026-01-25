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
end
# rubocop:enable Metrics/BlockLength
