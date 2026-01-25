# frozen_string_literal: true

class RubyCrawl
  # Base error class for all RubyCrawl errors
  class Error < StandardError; end

  # Raised when the Node.js service fails to start or is unavailable
  class ServiceError < Error; end

  # Raised when page navigation fails (timeout, DNS, SSL, etc.)
  class NavigationError < Error; end

  # Raised when a crawl operation times out
  class TimeoutError < Error; end

  # Raised when invalid configuration is provided
  class ConfigurationError < Error; end
end
