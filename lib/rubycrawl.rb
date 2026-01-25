# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

require_relative 'rubycrawl/version'
require_relative 'rubycrawl/railtie' if defined?(Rails)

# RubyCrawl provides a simple interface for crawling pages via a local Playwright service.
class RubyCrawl
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
    @host = options.fetch(:host, DEFAULT_HOST)
    @port = Integer(options.fetch(:port, DEFAULT_PORT))
    @node_dir = options.fetch(:node_dir, default_node_dir)
    @node_bin = options.fetch(:node_bin, ENV.fetch('RUBYCRAWL_NODE_BIN', nil)) || 'node'
    @node_log = options.fetch(:node_log, ENV.fetch('RUBYCRAWL_NODE_LOG', nil))
    @wait_until = options.fetch(:wait_until, nil)
    @block_resources = options.fetch(:block_resources, nil)
    @node_pid = nil
  end

  def crawl(url, wait_until: @wait_until, block_resources: @block_resources)
    ensure_service_running
    payload = build_payload(url, wait_until, block_resources)
    response = post_json('/crawl', payload)
    raise_node_error!(response)
    build_result(response)
  end

  private

  def build_payload(url, wait_until, block_resources)
    payload = { url: url }
    payload[:wait_until] = wait_until if wait_until
    payload[:block_resources] = block_resources unless block_resources.nil?
    payload
  end

  def raise_node_error!(response)
    return unless response.is_a?(Hash) && response['error']

    message = response['message'] ? " (#{response['message']})" : ''
    raise "rubycrawl node error: #{response['error']}#{message}"
  end

  def build_result(response)
    Result.new(
      text: response['text'].to_s,
      html: response['html'].to_s,
      links: Array(response['links']),
      metadata: response['metadata'].is_a?(Hash) ? response['metadata'] : {},
      markdown: response['markdown'].to_s
    )
  end

  def ensure_service_running
    return if healthy?

    start_service
    wait_until_healthy
  end

  def start_service
    raise "rubycrawl node service directory not found: #{@node_dir}" unless Dir.exist?(@node_dir)

    env = { 'RUBYCRAWL_NODE_PORT' => @port.to_s }
    out = @node_log ? File.open(@node_log, 'a') : File::NULL
    err = @node_log ? out : File::NULL
    @node_pid = Process.spawn(env, @node_bin, 'src/index.js', chdir: @node_dir, out: out, err: err)
    Process.detach(@node_pid)
  end

  def wait_until_healthy(timeout: 5)
    deadline = Time.now + timeout
    until Time.now > deadline
      return true if healthy?

      sleep 0.2
    end

    raise 'rubycrawl node service failed to start'
  end

  def healthy?
    uri = URI("http://#{@host}:#{@port}/health")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
      http.get(uri.request_uri)
    end
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def post_json(path, body)
    uri = URI("http://#{@host}:#{@port}#{path}")
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)

    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  rescue JSON::ParserError
    { 'error' => 'invalid_json_response' }
  end

  def default_node_dir
    File.expand_path('../node', __dir__)
  end
end
