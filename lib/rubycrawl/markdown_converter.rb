# frozen_string_literal: true

require 'uri'

class RubyCrawl
  # Converts HTML to Markdown using reverse_markdown gem.
  module MarkdownConverter
    # Patterns for relative URLs in markdown
    MARKDOWN_URL_PATTERNS = [
      %r{(!\[[^\]]*\])\((/[^)]+)\)}, # ![alt](/path)
      %r{(\[[^\]]*\])\((/[^)]+)\)}   # [text](/path)
    ].freeze

    module_function

    # Convert HTML to Markdown with resolved URLs.
    #
    # @param html [String] The HTML content to convert
    # @param base_url [String, nil] Base URL to resolve relative URLs
    # @param options [Hash] Options for conversion
    # @return [String] The Markdown content with absolute URLs
    def convert(html, base_url: nil, **options)
      return '' if html.nil? || html.empty?

      require_reverse_markdown
      markdown = ReverseMarkdown.convert(html, default_options.merge(options))
      base_url ? resolve_relative_urls(markdown, base_url) : markdown
    rescue LoadError
      warn '[rubycrawl] reverse_markdown gem not installed. Add it to your Gemfile for markdown support.'
      ''
    end

    # Resolve relative URLs in markdown to absolute URLs.
    #
    # @param markdown [String] The markdown content
    # @param base_url [String] The base URL to resolve against
    # @return [String] Markdown with absolute URLs
    def resolve_relative_urls(markdown, base_url)
      return markdown unless base_url

      base_uri = URI.parse(base_url)
      origin = "#{base_uri.scheme}://#{base_uri.host}"
      origin += ":#{base_uri.port}" unless [80, 443].include?(base_uri.port)

      MARKDOWN_URL_PATTERNS.reduce(markdown) do |md, pattern|
        md.gsub(pattern) { "#{::Regexp.last_match(1)}(#{origin}#{::Regexp.last_match(2)})" }
      end
    rescue URI::InvalidURIError
      markdown
    end

    def require_reverse_markdown
      require 'reverse_markdown'
    end

    def default_options
      {
        unknown_tags: :bypass,
        github_flavored: true,
        tag_border: ''
      }
    end
  end
end
