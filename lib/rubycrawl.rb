# frozen_string_literal: true

require_relative 'rubycrawl/version'
require_relative 'rubycrawl/errors'
require_relative 'rubycrawl/helpers'
require_relative 'rubycrawl/service_client'
require_relative 'rubycrawl/railtie' if defined?(Rails)

# RubyCrawl provides a simple interface for crawling pages via a local Playwright service.
class RubyCrawl
  include Helpers

  DEFAULT_HOST = '127.0.0.1'
  DEFAULT_PORT = 3344

  Result = Struct.new(:text, :html, :links, :metadata, :markdown, keyword_init: true)

  class << self
    def client
      @client ||= new
    end

    def crawl(url, **options)
      client.crawl(url, **options)
    end

    def configure(**options)
      @client = new(**options)
    end
  end

  def initialize(**options)
    load_options(options)
    build_service_client
  end

  def crawl(url, wait_until: @wait_until, block_resources: @block_resources, retries: @max_retries)
    validate_url!(url)
    @service_client.ensure_running
    with_retries(retries) do
      payload = build_payload(url, wait_until, block_resources)
      response = @service_client.post_json('/crawl', payload)
      raise_node_error!(response)
      build_result(response)
    end
  end

  private

  def raise_node_error!(response)
    return unless response.is_a?(Hash) && response['error']

    error_code = response['error']
    error_message = response['message'] || error_code
    raise error_class_for(error_code), error_message_for(error_code, error_message)
  end

  def with_retries(retries)
    attempt = 0
    begin
      yield
    rescue ServiceError, TimeoutError => e
      attempt += 1
      raise unless attempt < retries

      retry_with_backoff(attempt, retries, e)
      retry
    end
  end

  def load_options(options)
    @host = options.fetch(:host, DEFAULT_HOST)
    @port = Integer(options.fetch(:port, DEFAULT_PORT))
    @node_dir = options.fetch(:node_dir, default_node_dir)
    @node_bin = options.fetch(:node_bin, ENV.fetch('RUBYCRAWL_NODE_BIN', nil)) || 'node'
    @node_log = options.fetch(:node_log, ENV.fetch('RUBYCRAWL_NODE_LOG', nil))
    @wait_until = options.fetch(:wait_until, nil)
    @block_resources = options.fetch(:block_resources, nil)
    @max_retries = options.fetch(:max_retries, 3)
  end

  def build_service_client
    @service_client = ServiceClient.new(
      host: @host,
      port: @port,
      node_dir: @node_dir,
      node_bin: @node_bin,
      node_log: @node_log
    )
  end

  def retry_with_backoff(attempt, retries, error)
    backoff_seconds = 2**attempt
    warn "[rubycrawl] Retry #{attempt}/#{retries - 1} after #{backoff_seconds}s: #{error.message}"
    sleep(backoff_seconds)
  end

  def default_node_dir
    File.expand_path('../node', __dir__)
  end
end
