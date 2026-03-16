# frozen_string_literal: true

require 'set'

class RubyCrawl
  # BFS crawler that follows links with deduplication.
  class SiteCrawler
    # Page result yielded to the block with lazy clean_markdown.
    class PageResult
      attr_reader :url, :html, :links, :metadata, :depth

      def initialize(url:, html:, links:, metadata:, depth:)
        @url = url
        @html = html
        @links = links
        @metadata = metadata
        @depth = depth
      end

      # Returns clean markdown converted from the page HTML.
      # Relative URLs are resolved using the page's final_url.
      def clean_markdown
        @clean_markdown ||= MarkdownConverter.convert(html, base_url: final_url)
      end

      # The final URL after redirects.
      def final_url
        metadata['final_url'] || url
      end
    end

    def initialize(client, options = {})
      @client = client
      @max_pages = options.fetch(:max_pages, 50)
      @max_depth = options.fetch(:max_depth, 3)
      @same_host_only = options.fetch(:same_host_only, true)
      @wait_until = options.fetch(:wait_until, nil)
      @block_resources = options.fetch(:block_resources, nil)
      @max_attempts = options.fetch(:max_attempts, nil)
      @visited = Set.new
      @queue = []
      @session_id = nil
    end

    def crawl(start_url, &block)
      raise ArgumentError, 'Block required for site crawl' unless block_given?

      normalized = UrlNormalizer.normalize(start_url)
      raise ConfigurationError, "Invalid start URL: #{start_url}" unless normalized

      @base_url = normalized
      @session_id = @client.create_session
      enqueue(normalized, 0)
      process_queue(&block)
    ensure
      @client.destroy_session(@session_id) if @session_id
    end

    private

    def process_queue
      pages_crawled = 0

      while (item = @queue.shift) && pages_crawled < @max_pages
        url, depth = item
        next if @visited.include?(url)

        result = process_page(url, depth)
        next unless result

        yield result
        pages_crawled += 1
      end

      pages_crawled
    end

    def process_page(url, depth)
      @visited.add(url)
      result = crawl_page(url, depth)
      enqueue_links(result.links, depth + 1) if result && depth < @max_depth
      result
    end

    def crawl_page(url, depth)
      opts = { wait_until: @wait_until, block_resources: @block_resources, session_id: @session_id }
      opts[:max_attempts] = @max_attempts if @max_attempts
      result = @client.crawl(url, **opts)
      build_page_result(url, depth, result)
    rescue Error => e
      warn "[rubycrawl] Failed to crawl #{url}: #{e.message}"
      nil
    end

    def build_page_result(url, depth, result)
      PageResult.new(
        url: url,
        html: result.html,
        links: extract_urls(result.links),
        metadata: result.metadata,
        depth: depth
      )
    end

    def extract_urls(links)
      links.map { |link| link['url'] || link[:url] }.compact
    end

    def enqueue_links(links, depth)
      links.each do |link|
        normalized = UrlNormalizer.normalize(link, @base_url)
        next unless normalized
        next if @visited.include?(normalized)
        next if @same_host_only && !UrlNormalizer.same_host?(normalized, @base_url)

        enqueue(normalized, depth)
      end
    end

    def enqueue(url, depth)
      return if @visited.include?(url)

      @queue.push([url, depth])
    end
  end
end
