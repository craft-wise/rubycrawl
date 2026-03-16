# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'spec_helper'

# Canned Result used in unit tests — returned directly by the mocked Browser#crawl.
CANNED_RESULT = RubyCrawl::Result.new(
  html:       '<html><body><h1>Example Domain</h1><p>This domain is for use in examples.</p></body></html>',
  raw_text:   "Example Domain\nThis domain is for use in examples.",
  clean_html: '<h1>Example Domain</h1><p>This domain is for use in examples.</p>',
  links:      [{ 'url' => 'https://example.com/about', 'text' => 'About', 'title' => nil, 'rel' => nil }],
  metadata:   {
    'final_url'   => 'https://example.com/',
    'title'       => 'Example Domain',
    'description' => nil,
    'canonical'   => nil
  }
)

RSpec.describe RubyCrawl do
  # ──────────────────────────────────────────────────────────────
  # Unit tests — Browser is mocked, no network or Chrome required
  # ──────────────────────────────────────────────────────────────
  describe 'unit (mocked browser)' do
    before do
      allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl).and_return(CANNED_RESULT)
    end

    describe '.crawl' do
      subject(:result) { described_class.crawl('https://example.com') }

      it 'returns a Result' do
        expect(result).to be_a(RubyCrawl::Result)
      end

      it 'populates html, raw_text, clean_html, links, metadata' do
        expect(result.html).to eq(CANNED_RESULT.html)
        expect(result.raw_text).to eq(CANNED_RESULT.raw_text)
        expect(result.clean_html).to eq(CANNED_RESULT.clean_html)
        expect(result.links).to eq(CANNED_RESULT.links)
        expect(result.metadata).to include('final_url' => 'https://example.com/')
      end

      it 'clean_text is derived lazily from clean_html' do
        expect(result.clean_text).to be_a(String)
        expect(result.clean_text).to include('Example Domain')
        expect(result.clean_text).not_to include('<h1>')
      end

      it 'exposes final_url from metadata' do
        expect(result.final_url).to eq('https://example.com/')
      end

      it 'does not compute clean_markdown eagerly' do
        expect(result.clean_markdown?).to be false
        result.to_h
        expect(result.clean_markdown?).to be false
      end

      it 'computes clean_markdown lazily on first access' do
        expect(result.clean_markdown).to be_a(String)
        expect(result.clean_markdown?).to be true
      end

      it 'clean_markdown is derived from clean_html (no HTML tags)' do
        expect(result.clean_markdown).not_to include('<html>')
        expect(result.clean_markdown).to include('Example Domain')
      end
    end

    describe 'URL validation' do
      it 'raises ConfigurationError for invalid URL' do
        expect { described_class.crawl('not-a-url') }
          .to raise_error(RubyCrawl::ConfigurationError, /Invalid URL/)
      end

      it 'raises ConfigurationError for non-HTTP(S) URL' do
        expect { described_class.crawl('ftp://example.com') }
          .to raise_error(RubyCrawl::ConfigurationError, /Only HTTP\(S\) URLs are supported/)
      end

      it 'raises ConfigurationError for nil URL' do
        expect { described_class.crawl(nil) }
          .to raise_error(RubyCrawl::ConfigurationError, /Invalid URL/)
      end

      it 'raises ConfigurationError for invalid wait_until' do
        expect { described_class.crawl('https://example.com', wait_until: 'invalid') }
          .to raise_error(RubyCrawl::ConfigurationError, /Invalid wait_until/)
      end
    end

    describe 'error handling' do
      it 'raises NavigationError on navigation failure' do
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl)
          .and_raise(RubyCrawl::NavigationError, 'Navigation failed: net::ERR_NAME_NOT_RESOLVED')
        expect { described_class.crawl('https://example.com') }
          .to raise_error(RubyCrawl::NavigationError, /Navigation failed/)
      end

      it 'raises TimeoutError on timeout' do
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl)
          .and_raise(RubyCrawl::TimeoutError, 'Navigation timed out')
        client = described_class.new(max_attempts: 1)
        expect { client.crawl('https://example.com') }
          .to raise_error(RubyCrawl::TimeoutError)
      end

      it 'raises ServiceError on browser launch failure' do
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl)
          .and_raise(RubyCrawl::ServiceError, 'Failed to launch browser')
        client = described_class.new(max_attempts: 1)
        expect { client.crawl('https://example.com') }
          .to raise_error(RubyCrawl::ServiceError)
      end
    end

    describe 'retry behavior' do
      it 'retries on ServiceError and raises after max_attempts exhausted' do
        call_count = 0
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl) do
          call_count += 1
          raise RubyCrawl::ServiceError, 'transient failure'
        end

        client = described_class.new(max_attempts: 2)
        expect { client.crawl('https://example.com') }.to raise_error(RubyCrawl::ServiceError)
        expect(call_count).to eq(2)
      end

      it 'succeeds on retry if a transient failure resolves' do
        attempts = 0
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl) do
          attempts += 1
          raise RubyCrawl::ServiceError, 'transient' if attempts < 2

          CANNED_RESULT
        end

        client = described_class.new(max_attempts: 3)
        result = nil
        expect { result = client.crawl('https://example.com') }.not_to raise_error
        expect(result).to be_a(RubyCrawl::Result)
        expect(attempts).to eq(2)
      end

      it 'does not retry NavigationError' do
        call_count = 0
        allow_any_instance_of(RubyCrawl::Browser).to receive(:crawl) do
          call_count += 1
          raise RubyCrawl::NavigationError, 'page not found'
        end

        client = described_class.new(max_attempts: 3)
        expect { client.crawl('https://example.com') }.to raise_error(RubyCrawl::NavigationError)
        expect(call_count).to eq(1)
      end
    end

    describe 'error hierarchy' do
      it 'defines correct inheritance chain' do
        expect(RubyCrawl::Error).to be < StandardError
        expect(RubyCrawl::ServiceError).to be < RubyCrawl::Error
        expect(RubyCrawl::NavigationError).to be < RubyCrawl::Error
        expect(RubyCrawl::TimeoutError).to be < RubyCrawl::Error
        expect(RubyCrawl::ConfigurationError).to be < RubyCrawl::Error
      end
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Integration tests — require live Chrome and network
  # Run with: INTEGRATION=1 bundle exec rspec
  # ──────────────────────────────────────────────────────────────
  describe 'integration', :integration do
    describe '.crawl' do
      it 'returns a Result with HTML and metadata' do
        result = described_class.crawl('https://example.com')

        expect(result).to be_a(RubyCrawl::Result)
        expect(result.html).to be_a(String)
        expect(result.links).to be_a(Array)
        expect(result.metadata).to be_a(Hash)
        expect(result.metadata).to include('final_url')
      end

      it 'extracts raw_text and clean_text' do
        result = described_class.crawl('https://example.com')

        expect(result.raw_text).to be_a(String)
        expect(result.raw_text).not_to be_empty
        expect(result.clean_text).to be_a(String)
        expect(result.clean_text).not_to be_empty
        expect(result.clean_text).to include('Example Domain')
      end

      it 'extracts metadata fields' do
        result = described_class.crawl('https://example.com')
        expect(result.metadata.keys).to include('title', 'canonical')
      end
    end

    describe '.crawl_site' do
      it 'crawls multiple pages and yields PageResult objects' do
        pages = []
        count = described_class.crawl_site('https://example.com', max_pages: 3, max_depth: 1) do |page|
          pages << page
        end

        expect(count).to be > 0
        expect(pages.length).to eq(count)
        expect(pages.first).to be_a(RubyCrawl::SiteCrawler::PageResult)
        expect(pages.first.depth).to be_a(Integer)
      end

      it 'requires a block' do
        expect { described_class.crawl_site('https://example.com') }
          .to raise_error(ArgumentError, /Block required/)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
