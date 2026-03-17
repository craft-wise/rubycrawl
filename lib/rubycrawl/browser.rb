# frozen_string_literal: true

require 'ferrum'
require_relative 'result'
require_relative 'errors'
require_relative 'browser/extraction'

class RubyCrawl
  # Wraps Ferrum to provide a simple crawl interface.
  # Each crawl gets its own isolated page (own context = own cookies/storage).
  # Browser (Chrome) is launched once lazily and reused across crawls.
  class Browser
    BLOCKED_RESOURCE_TYPES = %w[image media font stylesheet].freeze

    def initialize(timeout: 30, headless: true, browser_options: {})
      @timeout         = timeout
      @headless        = headless
      @browser_options = browser_options
      @browser         = nil
      @mutex           = Mutex.new
    end

    # Crawl a URL and return a RubyCrawl::Result.
    #
    # @param url [String]
    # @param wait_until [String, nil] "load", "domcontentloaded", "networkidle", "commit"
    # @param block_resources [Boolean] block images/fonts/CSS/media for speed
    # @return [RubyCrawl::Result]
    def crawl(url, wait_until: nil, block_resources: true)
      page = lazy_browser.create_page(new_context: true)

      begin
        setup_resource_blocking(page) if block_resources
        navigate(page, url, wait_until.to_s)
        extract(page)
      rescue ::Ferrum::TimeoutError => e
        raise RubyCrawl::TimeoutError, "Navigation timed out: #{e.message}"
      rescue ::Ferrum::StatusError => e
        raise RubyCrawl::NavigationError, "Navigation failed: #{e.message}"
      rescue ::Ferrum::Error => e
        raise RubyCrawl::ServiceError, "Browser error: #{e.message}"
      ensure
        begin
          page&.close
        rescue StandardError
          nil
        end
      end
    end

    private

    # Lazy-initialise the Ferrum::Browser singleton.
    # Mutex prevents double-init in threaded environments (Puma).
    # Chrome launches after fork in forking servers (Unicorn) since @browser is nil in each worker.
    def lazy_browser
      @mutex.synchronize { @browser ||= launch_browser }
    rescue ::Ferrum::Error => e
      raise RubyCrawl::ServiceError, "Failed to launch browser: #{e.message}"
    end

    def launch_browser
      b = Ferrum::Browser.new(
        headless:        @headless,
        timeout:         @timeout,
        browser_options: @browser_options
      )
      at_exit do
        b.quit
      rescue StandardError
        nil # process is exiting anyway
      end
      b
    end

    def setup_resource_blocking(page)
      page.network.intercept
      page.on(:request) do |request|
        BLOCKED_RESOURCE_TYPES.include?(request.resource_type) ? request.abort : request.continue
      end
    end

    def navigate(page, url, wait_until)
      page.go_to(url)
      # go_to waits for load by default. networkidle needs an extra wait.
      page.network.wait_for_idle(connections: 0, duration: 0.5) if wait_until == 'networkidle'
    end

    def extract(page)
      html      = page.body
      final_url = page.current_url
      metadata  = page.evaluate(Extraction::EXTRACT_METADATA_JS)
      links     = page.evaluate(Extraction::EXTRACT_LINKS_JS)
      raw_text  = page.evaluate(Extraction::EXTRACT_RAW_TEXT_JS)
      content   = page.evaluate(Extraction::EXTRACT_CONTENT_JS)

      Result.new(
        html:       html,
        raw_text:   raw_text.to_s,
        clean_html: content['cleanHtml'].to_s,
        links:      Array(links),
        metadata:   { 'final_url' => final_url, 'extractor' => content['extractor'] }.merge(metadata || {})
      )
    end
  end
end
