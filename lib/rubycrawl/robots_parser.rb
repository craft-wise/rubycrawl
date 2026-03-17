# frozen_string_literal: true

require 'net/http'
require 'uri'

class RubyCrawl
  # Fetches and parses robots.txt for a given site.
  # Supports User-agent: *, Disallow, Allow, and Crawl-delay directives.
  # Fails open — any fetch/parse error allows all URLs.
  class RobotsParser
    # Fetch robots.txt from base_url and return a parser instance.
    # Returns a permissive (allow-all) instance on any network error.
    def self.fetch(base_url)
      uri = URI.join(base_url, '/robots.txt')
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl:      uri.scheme == 'https',
                                 open_timeout: 5,
                                 read_timeout: 5) do |http|
        http.get(uri.request_uri)
      end
      new(response.is_a?(Net::HTTPOK) ? response.body : '')
    rescue StandardError
      new('') # network error or invalid URL → allow everything
    end

    def initialize(content)
      @rules = parse(content.to_s)
    end

    # Returns true if the given URL is allowed to be crawled.
    def allowed?(url)
      path = URI.parse(url).path
      path = '/' if path.nil? || path.empty?

      # Allow rules take precedence over Disallow when both match.
      return true if @rules[:allow].any? { |rule| path_matches?(path, rule) }
      return false if @rules[:disallow].any? { |rule| path_matches?(path, rule) }

      true
    rescue URI::InvalidURIError
      true
    end

    # Returns the Crawl-delay value in seconds, or nil if not specified.
    def crawl_delay
      @rules[:crawl_delay]
    end

    private

    def parse(content)
      rules = { allow: [], disallow: [], crawl_delay: nil }
      in_relevant_section = false

      content.each_line do |raw_line|
        line = raw_line.strip.sub(/#.*$/, '').strip
        next if line.empty?

        key, value = line.split(':', 2).map(&:strip)
        next unless key && value

        case key.downcase
        when 'user-agent'
          in_relevant_section = (value == '*')
        when 'disallow'
          rules[:disallow] << value if in_relevant_section && !value.empty?
        when 'allow'
          rules[:allow] << value if in_relevant_section && !value.empty?
        when 'crawl-delay'
          rules[:crawl_delay] = value.to_f if in_relevant_section && value.match?(/\A\d+(\.\d+)?\z/)
        end
      end

      rules
    end

    # Matches a URL path against a robots.txt rule pattern.
    # Supports * (wildcard) and $ (end-of-string anchor).
    def path_matches?(path, rule)
      return false if rule.empty?

      pattern = Regexp.escape(rule).gsub('\*', '.*').gsub('\$', '\z')
      path.match?(/\A#{pattern}/)
    end
  end
end
