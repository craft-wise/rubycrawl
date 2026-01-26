# frozen_string_literal: true

require 'uri'

class RubyCrawl
  # Helper methods for payloads, validation, and errors.
  module Helpers
    private

    def validate_url!(url)
      uri = URI.parse(url)

      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise ConfigurationError, "Invalid URL: Only HTTP(S) URLs are supported, got: #{url}"
      end

      if uri.host&.match?(/^(localhost|127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01]))/)
        warn '[rubycrawl] Warning: Crawling internal/private IP addresses'
      end
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid URL: #{e.message}"
    end

    def build_payload(url, wait_until, block_resources)
      payload = { url: url }
      payload[:wait_until] = wait_until if wait_until
      payload[:block_resources] = block_resources unless block_resources.nil?
      payload
    end

    def build_result(response)
      Result.new(
        text: response['text'].to_s,
        html: response['html'].to_s,
        links: Array(response['links']),
        metadata: response['metadata'].is_a?(Hash) ? response['metadata'] : {}
      )
    end

    def error_class_for(error_code)
      case error_code
      when 'navigation_timeout', 'crawl_timeout'
        TimeoutError
      when 'navigation_failed', 'crawl_failed'
        NavigationError
      when 'invalid_json', 'invalid_json_response'
        ServiceError
      else
        Error
      end
    end

    def error_message_for(error_code, error_message)
      case error_code
      when 'navigation_timeout', 'crawl_timeout'
        "Crawl timeout: #{error_message}"
      when 'navigation_failed', 'crawl_failed'
        "Navigation failed: #{error_message}"
      when 'invalid_json', 'invalid_json_response'
        "Node service returned invalid JSON: #{error_message}"
      else
        "Crawl error [#{error_code}]: #{error_message}"
      end
    end
  end
end
