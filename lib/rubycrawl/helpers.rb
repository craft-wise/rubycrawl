# frozen_string_literal: true

require 'uri'

class RubyCrawl
  # Validation helpers mixed into RubyCrawl.
  module Helpers
    VALID_WAIT_UNTIL = %w[load domcontentloaded networkidle commit].freeze

    private

    def validate_url!(url)
      uri = URI.parse(url)

      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise ConfigurationError, "Invalid URL: Only HTTP(S) URLs are supported, got: #{url}"
      end

      if uri.host&.match?(/^(localhost|127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01]))/)
        warn '[rubycrawl] Warning: Crawling internal/private IP addresses'
      end
    rescue URI::InvalidURIError, TypeError => e
      raise ConfigurationError, "Invalid URL: #{e.message}"
    end

    def validate_wait_until!(wait_until)
      return unless wait_until
      return if VALID_WAIT_UNTIL.include?(wait_until.to_s)

      raise ConfigurationError,
            "Invalid wait_until: #{wait_until.inspect}. Must be one of: #{VALID_WAIT_UNTIL.join(', ')}"
    end
  end
end
