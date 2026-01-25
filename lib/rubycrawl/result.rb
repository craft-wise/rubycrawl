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
    #
    # @return [String] Markdown content
    def markdown
      @markdown ||= MarkdownConverter.convert(html)
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
