# frozen_string_literal: true

class RubyCrawl
  # Result object with lazy markdown conversion.
  class Result
    attr_reader :text, :html, :links, :metadata

    def initialize(text:, html:, links:, metadata:, markdown: nil)
      @text = text
      @html = html
      @links = links
      @metadata = metadata
      @markdown = markdown unless markdown.to_s.empty?
    end

    # Returns markdown, converting from HTML lazily if needed.
    # Relative URLs are resolved using the page's final_url.
    #
    # @return [String] Markdown content with absolute URLs
    def markdown
      @markdown ||= MarkdownConverter.convert(html, base_url: final_url)
    end

    # The final URL after redirects.
    #
    # @return [String, nil]
    def final_url
      metadata['final_url'] || metadata[:final_url]
    end

    # Check if markdown has been computed.
    #
    # @return [Boolean]
    def markdown?
      !@markdown.nil?
    end

    def to_h
      {
        text: text,
        html: html,
        links: links,
        metadata: metadata,
        markdown: markdown
      }
    end
  end
end
