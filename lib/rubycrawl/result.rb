# frozen_string_literal: true

require 'cgi'

class RubyCrawl
  # Immutable result object returned from every crawl.
  # clean_text and clean_markdown are both derived lazily from clean_html so
  # they have consistent content coverage (including hidden/collapsed elements).
  class Result
    attr_reader :raw_text, :clean_html, :html, :links, :metadata

    def initialize(raw_text:, clean_html:, html:, links:, metadata:)
      @raw_text   = raw_text
      @clean_html = clean_html
      @html       = html
      @links      = links
      @metadata   = metadata
    end

    # Plain text derived from noise-stripped HTML.
    # Captures hidden/collapsed content (accordions, tabs) that innerText misses.
    # Lazy — computed on first access.
    #
    # @return [String]
    def clean_text
      @clean_text ||= html_to_text(clean_html.empty? ? html : clean_html)
    end

    # Markdown derived from noise-stripped HTML.
    # Preserves document structure (headings, lists, links).
    # Lazy — computed on first access.
    #
    # @return [String]
    def clean_markdown
      source = clean_html.empty? ? html : clean_html
      @clean_markdown ||= MarkdownConverter.convert(source, base_url: final_url)
    end

    # The final URL after redirects.
    # @return [String, nil]
    def final_url
      metadata['final_url']
    end

    # @return [Boolean]
    def clean_markdown?
      !@clean_markdown.nil?
    end

    def to_h
      {
        raw_text:       raw_text,
        clean_text:     @clean_text,
        clean_html:     clean_html,
        html:           html,
        links:          links,
        metadata:       metadata,
        clean_markdown: @clean_markdown
      }
    end

    private

    # Convert HTML to plain text without any external dependencies.
    # Block-level elements (p, div, h1-h6, li, br, etc.) become newlines
    # so paragraph structure is preserved. HTML entities are unescaped.
    def html_to_text(source)
      text = source
             .gsub(%r{</?(p|div|h[1-6]|li|br|tr|section|article|blockquote|pre)[^>]*>}i, "\n")
             .gsub(/<[^>]+>/, '')
      CGI.unescapeHTML(text)
         .gsub(/[ \t]+/, ' ')
         .gsub(/ *\n */, "\n")
         .gsub(/\n{3,}/, "\n\n")
         .strip
    end
  end
end
