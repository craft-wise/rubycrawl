# frozen_string_literal: true

class RubyCrawl
  # Result object with lazy clean_markdown conversion.
  class Result
    attr_reader :text, :html, :links, :metadata

    def initialize(text:, html:, links:, metadata:)
      @text = text
      @html = html
      @links = links
      @metadata = metadata
    end

    # Returns clean markdown converted from the page HTML.
    # Relative URLs are resolved using the page's final_url.
    #
    # @return [String] Markdown content with absolute URLs
    def clean_markdown
      @clean_markdown ||= MarkdownConverter.convert(html, base_url: final_url)
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
        text: text,
        html: html,
        links: links,
        metadata: metadata,
        clean_markdown: @clean_markdown
      }
    end
  end
end
