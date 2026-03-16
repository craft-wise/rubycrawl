# frozen_string_literal: true

require_relative 'rubycrawl/version'
require_relative 'rubycrawl/errors'
require_relative 'rubycrawl/helpers'
require_relative 'rubycrawl/browser'
require_relative 'rubycrawl/url_normalizer'
require_relative 'rubycrawl/markdown_converter'
require_relative 'rubycrawl/result'
require_relative 'rubycrawl/site_crawler'
require_relative 'rubycrawl/railtie' if defined?(Rails)

# RubyCrawl — pure Ruby web crawler with full JavaScript rendering via Ferrum.
class RubyCrawl
  include Helpers

  class << self
    def client
      @client ||= new
    end

    # Crawl a single URL and return a Result.
    # @param url [String]
    # @param options [Hash] wait_until:, block_resources:, max_attempts:
    # @return [RubyCrawl::Result]
    def crawl(url, **options)
      client.crawl(url, **options)
    end

    # Crawl multiple pages starting from a URL, following links.
    # Yields each page result to the block as it is crawled.
    #
    # @param url [String] The starting URL
    # @param max_pages [Integer] Maximum number of pages to crawl (default: 50)
    # @param max_depth [Integer] Maximum link depth from start URL (default: 3)
    # @param same_host_only [Boolean] Only follow links on the same host (default: true)
    # @yield [page] Yields each page result as it is crawled
    # @yieldparam page [SiteCrawler::PageResult]
    # @return [Integer] Number of pages crawled
    #
    # @example
    #   RubyCrawl.crawl_site("https://example.com", max_pages: 100) do |page|
    #     Page.create!(url: page.url, content: page.clean_text, depth: page.depth)
    #   end
    def crawl_site(url, ...)
      client.crawl_site(url, ...)
    end

    def configure(**options)
      @client = new(**options)
    end
  end

  def initialize(**options)
    load_options(options)
    @browser = Browser.new(
      timeout:         @timeout,
      headless:        @headless,
      browser_options: @browser_options
    )
  end

  def crawl(url, wait_until: @wait_until, block_resources: @block_resources, max_attempts: @max_attempts)
    validate_url!(url)
    validate_wait_until!(wait_until)
    with_retries(max_attempts) do
      @browser.crawl(url, wait_until: wait_until, block_resources: block_resources)
    end
  end

  def crawl_site(url, **options, &block)
    crawler_options = build_crawler_options(options)
    SiteCrawler.new(self, crawler_options).crawl(url, &block)
  end

  private

  def load_options(options)
    @wait_until      = options.fetch(:wait_until, nil)
    @block_resources = options.fetch(:block_resources, nil)
    @max_attempts    = options.fetch(:max_attempts, 3)
    @timeout         = options.fetch(:timeout, 30)
    @headless        = options.fetch(:headless, true)
    @browser_options = options.fetch(:browser_options, {})
  end

  def with_retries(max_attempts)
    attempt = 0
    begin
      yield
    rescue ServiceError, TimeoutError => e
      attempt += 1
      raise unless attempt < max_attempts

      backoff = 2**attempt
      warn "[rubycrawl] Attempt #{attempt + 1}/#{max_attempts} failed, retrying in #{backoff}s: #{e.message}"
      sleep(backoff)
      retry
    end
  end

  def build_crawler_options(options)
    {
      max_pages:       options.fetch(:max_pages, 50),
      max_depth:       options.fetch(:max_depth, 3),
      same_host_only:  options.fetch(:same_host_only, true),
      wait_until:      options.fetch(:wait_until, @wait_until),
      block_resources: options.fetch(:block_resources, @block_resources),
      max_attempts:    options.fetch(:max_attempts, @max_attempts)
    }
  end
end
