# frozen_string_literal: true

require 'uri'
require 'set'

class RubyCrawl
  # Normalizes URLs for deduplication.
  module UrlNormalizer
    module_function

    def normalize(url, base_url = nil)
      uri = parse_uri(url, base_url)
      return nil unless uri&.host

      normalize_uri_parts(uri)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def normalize_uri_parts(uri)
      uri.scheme = uri.scheme&.downcase
      uri.host = uri.host&.downcase
      uri.path = normalize_path(uri.path)
      uri.fragment = nil
      uri.query = normalize_query(uri.query)
    end

    def same_host?(url, base_url)
      uri = URI.parse(url)
      base_uri = URI.parse(base_url)
      canonical_host(uri.host) == canonical_host(base_uri.host)
    rescue URI::InvalidURIError
      false
    end

    def canonical_host(host)
      host&.downcase&.delete_prefix('www.')
    end

    def parse_uri(url, base_url)
      uri = URI.parse(url)
      return uri if uri.absolute?
      return nil unless base_url

      URI.join(base_url, url)
    rescue URI::InvalidURIError
      nil
    end

    def normalize_path(path)
      return '/' if path.nil? || path.empty?

      # Remove trailing slash except for root
      path = path.chomp('/') if path.length > 1
      path
    end

    def normalize_query(query)
      return nil if query.nil? || query.empty?

      # Remove tracking params
      tracking_params = %w[utm_source utm_medium utm_campaign utm_term utm_content fbclid gclid]
      params = URI.decode_www_form(query).reject { |k, _| tracking_params.include?(k.downcase) }
      return nil if params.empty?

      URI.encode_www_form(params.sort)
    rescue ArgumentError
      query
    end
  end
end
