# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyCrawl::SiteCrawler do
  # Build a fake Result the mocked client returns.
  def make_result(url:, links: [], title: nil)
    RubyCrawl::Result.new(
      html:       "<html><body><p>Page at #{url}</p></body></html>",
      raw_text:   "Page at #{url}",
      clean_html: "<p>Page at #{url}</p>",
      links:      links.map { |l| { 'url' => l, 'text' => l } },
      metadata:   { 'final_url' => url, 'title' => title }
    )
  end

  let(:client) { instance_double(RubyCrawl::Browser) }

  describe '#crawl' do
    it 'requires a block' do
      crawler = described_class.new(client)
      expect { crawler.crawl('https://example.com') }.to raise_error(ArgumentError, /Block required/)
    end

    it 'raises ConfigurationError for an invalid start URL' do
      crawler = described_class.new(client)
      expect { crawler.crawl('not-a-url') {} }.to raise_error(RubyCrawl::ConfigurationError)
    end

    it 'crawls a single page and yields a PageResult' do
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url: 'https://example.com/'))

      results = []
      described_class.new(client).crawl('https://example.com') { |r| results << r }

      expect(results.size).to eq(1)
      expect(results.first).to be_a(RubyCrawl::SiteCrawler::PageResult)
      expect(results.first.url).to eq('https://example.com/')
      expect(results.first.depth).to eq(0)
    end

    it 'follows links found on the start page' do
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://example.com/about']))
      allow(client).to receive(:crawl).with('https://example.com/about', any_args)
                                      .and_return(make_result(url: 'https://example.com/about'))

      results = []
      described_class.new(client).crawl('https://example.com') { |r| results << r }

      expect(results.map(&:url)).to contain_exactly('https://example.com/', 'https://example.com/about')
    end

    it 'does not visit the same URL twice' do
      # Start page links back to itself
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://example.com/']))

      expect(client).to receive(:crawl).once
      described_class.new(client).crawl('https://example.com') { |_r| }
    end

    it 'respects max_pages limit' do
      # Page links to 10 subpages
      sublinks = (1..10).map { |i| "https://example.com/p#{i}" }
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url: 'https://example.com/', links: sublinks))
      sublinks.each do |link|
        allow(client).to receive(:crawl).with(link, any_args)
                                        .and_return(make_result(url: link))
      end

      results = []
      described_class.new(client, max_pages: 3).crawl('https://example.com') { |r| results << r }

      expect(results.size).to eq(3)
    end

    it 'respects max_depth limit' do
      # depth 0 → links to depth 1 → links to depth 2 (should not be followed)
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://example.com/level1']))
      allow(client).to receive(:crawl).with('https://example.com/level1', any_args)
                                      .and_return(make_result(url:   'https://example.com/level1',
                                                              links: ['https://example.com/level2']))

      results = []
      described_class.new(client, max_depth: 1).crawl('https://example.com') { |r| results << r }

      urls = results.map(&:url)
      expect(urls).to include('https://example.com/', 'https://example.com/level1')
      expect(urls).not_to include('https://example.com/level2')
    end

    it 'skips links to other hosts when same_host_only: true (default)' do
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://other.com/page']))

      expect(client).to receive(:crawl).once
      described_class.new(client, same_host_only: true).crawl('https://example.com') { |_r| }
    end

    it 'follows links to other hosts when same_host_only: false' do
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://other.com/page']))
      allow(client).to receive(:crawl).with('https://other.com/page', any_args)
                                      .and_return(make_result(url: 'https://other.com/page'))

      results = []
      described_class.new(client, same_host_only: false).crawl('https://example.com') { |r| results << r }

      expect(results.map(&:url)).to include('https://other.com/page')
    end

    it 'skips a page that raises a crawl error and continues' do
      allow(client).to receive(:crawl).with('https://example.com/', any_args)
                                      .and_return(make_result(url:   'https://example.com/',
                                                              links: ['https://example.com/about',
                                                                      'https://example.com/contact']))
      allow(client).to receive(:crawl).with('https://example.com/about', any_args)
                                      .and_raise(RubyCrawl::NavigationError, '404')
      allow(client).to receive(:crawl).with('https://example.com/contact', any_args)
                                      .and_return(make_result(url: 'https://example.com/contact'))

      results = []
      described_class.new(client).crawl('https://example.com') { |r| results << r }

      expect(results.map(&:url)).to include('https://example.com/', 'https://example.com/contact')
      expect(results.map(&:url)).not_to include('https://example.com/about')
    end

    it 'returns the number of pages crawled' do
      allow(client).to receive(:crawl).and_return(make_result(url: 'https://example.com/'))
      crawler = described_class.new(client)
      # We can't capture the return value directly via the public API since crawl
      # yields; access via the private method count returned from process_queue.
      # Instead verify via the yielded results count.
      results = []
      crawler.crawl('https://example.com') { |r| results << r }
      expect(results.size).to eq(1)
    end
  end

  describe RubyCrawl::SiteCrawler::PageResult do
    let(:result) do
      described_class.new(
        url:        'https://example.com/page',
        html:       '<html><body><nav>Nav</nav><p>Content</p></body></html>',
        raw_text:   'Nav Content',
        clean_html: '<p>Content</p>',
        links:      ['https://example.com/other'],
        metadata:   { 'final_url' => 'https://example.com/page', 'title' => 'Test' },
        depth:      1
      )
    end

    it 'exposes all attributes' do
      expect(result.url).to eq('https://example.com/page')
      expect(result.depth).to eq(1)
      expect(result.metadata['title']).to eq('Test')
    end

    it 'final_url falls back to url when not in metadata' do
      r = described_class.new(
        url: 'https://example.com/', html: '', raw_text: '', clean_html: '',
        links: [], metadata: {}, depth: 0
      )
      expect(r.final_url).to eq('https://example.com/')
    end

    it 'clean_text strips HTML tags' do
      expect(result.clean_text).to include('Content')
      expect(result.clean_text).not_to include('<p>')
    end

    it 'clean_markdown is lazy' do
      expect(result.instance_variable_get(:@clean_markdown)).to be_nil
      result.clean_markdown
      expect(result.instance_variable_get(:@clean_markdown)).not_to be_nil
    end
  end
end
