# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'spec_helper'

# Canned response mirroring the Node service JSON for unit tests.
CANNED_CRAWL_RESPONSE = {
  'ok' => true,
  'url' => 'https://example.com',
  'html' => '<html><body><h1>Example Domain</h1><p>This domain is for use in examples.</p></body></html>',
  'raw_text' => "Example Domain\nThis domain is for use in examples.",
  'clean_text' => "Example Domain\n\nThis domain is for use in examples.",
  'clean_html' => '<h1>Example Domain</h1><p>This domain is for use in examples.</p>',
  'links' => [{ 'url' => 'https://example.com/about', 'text' => 'About', 'title' => nil, 'rel' => nil }],
  'metadata' => {
    'status' => 200,
    'final_url' => 'https://example.com/',
    'title' => 'Example Domain',
    'description' => nil,
    'canonical' => nil
  }
}.freeze

RSpec.describe RubyCrawl do
  # ──────────────────────────────────────────────────────────────
  # Unit tests — Node service is mocked, no network required
  # ──────────────────────────────────────────────────────────────
  describe 'unit (mocked Node service)' do
    before do
      allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:ensure_running)
      allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json)
        .with('/crawl', anything)
        .and_return(CANNED_CRAWL_RESPONSE)
    end

    describe '.crawl' do
      subject(:result) { described_class.crawl('https://example.com') }

      it 'returns a Result' do
        expect(result).to be_a(RubyCrawl::Result)
      end

      it 'populates html, raw_text, clean_text, clean_html, links, metadata' do
        expect(result.html).to eq(CANNED_CRAWL_RESPONSE['html'])
        expect(result.raw_text).to eq(CANNED_CRAWL_RESPONSE['raw_text'])
        expect(result.clean_text).to eq(CANNED_CRAWL_RESPONSE['clean_text'])
        expect(result.clean_html).to eq(CANNED_CRAWL_RESPONSE['clean_html'])
        expect(result.links).to eq(CANNED_CRAWL_RESPONSE['links'])
        expect(result.metadata).to include('status' => 200, 'final_url' => 'https://example.com/')
      end

      it 'content differs from raw_text (smart extraction vs full body)' do
        expect(result.clean_text).not_to eq(result.raw_text)
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

      it 'clean_markdown is derived from clean_html' do
        expect(result.clean_markdown).not_to include('<html>')
        expect(result.clean_markdown).to include('Example Domain')
      end
    end

    describe 'error handling' do
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

      it 'raises NavigationError when Node returns crawl_failed' do
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json)
          .and_return({ 'error' => 'crawl_failed', 'message' => 'net::ERR_NAME_NOT_RESOLVED' })
        expect { described_class.crawl('https://example.com') }
          .to raise_error(RubyCrawl::NavigationError, /Navigation failed/)
      end

      it 'raises ServiceError when Node returns session_create_failed' do
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json)
          .and_return({ 'error' => 'session_create_failed', 'message' => 'browser crashed' })
        client = described_class.new(max_attempts: 1)
        expect { client.crawl('https://example.com') }
          .to raise_error(RubyCrawl::ServiceError, /Service error/)
      end

      it 'raises ServiceError on connection refused' do
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:ensure_running)
          .and_raise(RubyCrawl::ServiceError, 'Cannot connect to node service')
        client = described_class.new(max_attempts: 1)
        expect { client.crawl('https://example.com') }
          .to raise_error(RubyCrawl::ServiceError)
      end
    end

    describe 'retry behavior' do
      it 'retries on ServiceError and eventually raises after max_attempts' do
        call_count = 0
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json) do
          call_count += 1
          raise RubyCrawl::ServiceError, 'transient failure'
        end

        client = described_class.new(max_attempts: 2)
        expect { client.crawl('https://example.com') }.to raise_error(RubyCrawl::ServiceError)
        expect(call_count).to eq(2) # 2 total attempts with max_attempts: 2
      end

      it 'succeeds on retry if a transient failure resolves' do
        attempts = 0
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json) do
          attempts += 1
          raise RubyCrawl::ServiceError, 'transient' if attempts < 2

          CANNED_CRAWL_RESPONSE
        end

        client = described_class.new(max_attempts: 3)
        result = nil
        expect { result = client.crawl('https://example.com') }.not_to raise_error
        expect(result).to be_a(RubyCrawl::Result)
        expect(attempts).to eq(2)
      end
    end

    describe 'session management (mocked)' do
      before do
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json)
          .with('/session/create', anything)
          .and_return({ 'ok' => true, 'session_id' => 'sess_abc123' })
        allow_any_instance_of(RubyCrawl::ServiceClient).to receive(:post_json)
          .with('/session/destroy', anything)
          .and_return({ 'ok' => true })
      end

      it 'creates a session and returns a session_id string' do
        session_id = described_class.create_session
        expect(session_id).to eq('sess_abc123')
      end

      it 'destroys a session without raising' do
        expect { described_class.destroy_session('sess_abc123') }.not_to raise_error
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
  # Integration tests — require live Node service and network
  # Run with: bundle exec rspec --tag integration
  # ──────────────────────────────────────────────────────────────
  describe 'integration', :integration do
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
        expect(result.metadata.keys).to include('title', 'description', 'canonical')
      end

      it 'extracts raw_text and smart content' do
        result = described_class.crawl('https://example.com')
        expect(result.raw_text).to be_a(String)
        expect(result.raw_text).not_to be_empty
        expect(result.clean_text).to be_a(String)
        expect(result.clean_text).not_to be_empty
        expect(result.clean_text).to include('Example Domain')
      end
    end

    describe 'session management' do
      it 'creates and destroys sessions' do
        session_id = described_class.create_session
        expect(session_id).to be_a(String)
        expect(session_id).to start_with('sess_')
        expect { described_class.destroy_session(session_id) }.not_to raise_error
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
        expect { described_class.destroy_session('sess_nonexistent') }.not_to raise_error
      end
    end

    describe '.crawl_site' do
      it 'crawls multiple pages and yields results' do
        pages = []
        pages_crawled = described_class.crawl_site(
          'https://example.com',
          max_pages: 3,
          max_depth: 1
        ) { |page| pages << page }

        expect(pages_crawled).to be > 0
        expect(pages.length).to eq(pages_crawled)
        expect(pages.first).to be_a(RubyCrawl::SiteCrawler::PageResult)
        expect(pages.first.url).to be_a(String)
        expect(pages.first.html).to be_a(String)
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
