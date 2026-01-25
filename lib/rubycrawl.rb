# frozen_string_literal: true

require_relative 'rubycrawl/version'
require_relative 'rubycrawl/errors'
require_relative 'rubycrawl/helpers'
require_relative 'rubycrawl/service_client'
require_relative 'rubycrawl/url_normalizer'
require_relative 'rubycrawl/markdown_converter'
require_relative 'rubycrawl/result'
require_relative 'rubycrawl/site_crawler'
require_relative 'rubycrawl/railtie' if defined?(Rails)

# RubyCrawl provides a simple interface for crawling pages via a local Playwright service.
class RubyCrawl
  include Helpers

  DEFAULT_HOST = '127.0.0.1'
  DEFAULT_PORT = 3344

  class << self
    def client
      @client ||= new
    end

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
    # @yieldparam page [SiteCrawler::PageResult] The crawled page result
    # @return [Integer] Number of pages crawled
    #
    # @example Save pages to database
    #   RubyCrawl.crawl_site("https://example.com", max_pages: 100) do |page|
    #     Page.create!(url: page.url, html: page.html, depth: page.depth)
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
    build_service_client
  end

  def crawl(url, wait_until: @wait_until, block_resources: @block_resources, retries: @max_retries)
    validate_url!(url)
    @service_client.ensure_running
    with_retries(retries) do
      payload = build_payload(url, wait_until, block_resources)
      response = @service_client.post_json('/crawl', payload)
      raise_node_error!(response)
      build_result(response)
    end
  end

  # Crawl multiple pages starting from a URL, following links.
  # @see RubyCrawl.crawl_site
  def crawl_site(url, **options, &block)
    @service_client.ensure_running
    crawler_options = build_crawler_options(options)
    crawler = SiteCrawler.new(self, crawler_options)
    crawler.crawl(url, &block)
  end

  private

  def raise_node_error!(response)
    return unless response.is_a?(Hash) && response['error']

    error_code = response['error']
    error_message = response['message'] || error_code
    raise error_class_for(error_code), error_message_for(error_code, error_message)
  end

  def with_retries(retries)
    attempt = 0
    begin
      yield
    rescue ServiceError, TimeoutError => e
      attempt += 1
      raise unless attempt < retries

      retry_with_backoff(attempt, retries, e)
      retry
    end
  end

  def load_options(options)
    @host = options.fetch(:host, DEFAULT_HOST)
    @port = Integer(options.fetch(:port, DEFAULT_PORT))
    @node_dir = options.fetch(:node_dir, default_node_dir)
    @node_bin = options.fetch(:node_bin, ENV.fetch('RUBYCRAWL_NODE_BIN', nil)) || 'node'
    @node_log = options.fetch(:node_log, ENV.fetch('RUBYCRAWL_NODE_LOG', nil))
    @wait_until = options.fetch(:wait_until, nil)
    @block_resources = options.fetch(:block_resources, nil)
    @max_retries = options.fetch(:max_retries, 3)
  end

  def build_service_client
    @service_client = ServiceClient.new(
      host: @host,
      port: @port,
      node_dir: @node_dir,
      node_bin: @node_bin,
      node_log: @node_log
    )
  end

  def retry_with_backoff(attempt, retries, error)
    backoff_seconds = 2**attempt
    warn "[rubycrawl] Retry #{attempt}/#{retries - 1} after #{backoff_seconds}s: #{error.message}"
    sleep(backoff_seconds)
  end

  def build_crawler_options(options)
    {
      max_pages: options.fetch(:max_pages, 50),
      max_depth: options.fetch(:max_depth, 3),
      same_host_only: options.fetch(:same_host_only, true),
      wait_until: options.fetch(:wait_until, @wait_until),
      block_resources: options.fetch(:block_resources, @block_resources)
    }
  end

  def default_node_dir
    File.expand_path('../node', __dir__)
  end
end
