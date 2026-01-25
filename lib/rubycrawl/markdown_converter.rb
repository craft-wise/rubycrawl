# frozen_string_literal: true

class RubyCrawl
  # Converts HTML to Markdown using reverse_markdown gem.
  module MarkdownConverter
    module_function

    # Convert HTML to Markdown.
    #
    # @param html [String] The HTML content to convert
    # @param options [Hash] Options for conversion
    # @option options [Boolean] :unknown_tags (:bypass) How to handle unknown tags
    # @option options [Boolean] :github_flavored (true) Use GitHub-flavored markdown
    # @return [String] The Markdown content
    def convert(html, options = {})
      return '' if html.nil? || html.empty?

      require_reverse_markdown
      ReverseMarkdown.convert(html, default_options.merge(options))
    rescue LoadError
      warn '[rubycrawl] reverse_markdown gem not installed. Add it to your Gemfile for markdown support.'
      ''
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
