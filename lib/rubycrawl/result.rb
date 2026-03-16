# frozen_string_literal: true

class RubyCrawl
  # Result object with lazy clean_markdown conversion.
  class Result
    attr_reader :raw_text, :clean_text, :clean_html, :html, :links, :metadata

    def initialize(raw_text:, clean_text:, clean_html:, html:, links:, metadata:)
      @raw_text   = raw_text
      @clean_text = clean_text
      @clean_html = clean_html
      @html       = html
      @links      = links
      @metadata   = metadata
    end

    # Converts the noise-stripped HTML to Markdown.
    # Uses clean_html (nav/header/footer removed) when available, falls back to full html.
    # Relative URLs are resolved using the page's final_url.
    # Lazy-loaded — only computed on first access.
    #
    # @return [String] Markdown with absolute URLs
    def clean_markdown
      source = clean_html.empty? ? html : clean_html
      @clean_markdown ||= MarkdownConverter.convert(source, base_url: final_url)
    end

    # The final URL after redirects.
    #
    # @return [String, nil]
    def final_url
      metadata['final_url']
    end

    # Check if clean_markdown has been computed.
    #
    # @return [Boolean]
    def clean_markdown?
      !@clean_markdown.nil?
    end

    def to_h
      {
        raw_text: raw_text,
        clean_text: clean_text,
        clean_html: clean_html,
        html: html,
        links: links,
        metadata: metadata,
        clean_markdown: @clean_markdown
      }
    end
  end
end
