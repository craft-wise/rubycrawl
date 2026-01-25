# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

class RubyCrawl
  # Handles node service lifecycle and HTTP requests.
  class ServiceClient
    def initialize(host:, port:, node_dir:, node_bin:, node_log:)
      @host = host
      @port = Integer(port)
      @node_dir = node_dir
      @node_bin = node_bin
      @node_log = node_log
      @node_pid = nil
    end

    def ensure_running
      return if healthy?

      start_service
      wait_until_healthy
    end

    def post_json(path, body)
      uri = URI("http://#{@host}:#{@port}#{path}")
      request = build_request(uri, body)
      response = perform_request(uri, request)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ServiceError, "Node service returned invalid JSON: #{e.message}"
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
      raise ServiceError, "Cannot connect to node service at #{uri}: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "Request to node service timed out: #{e.message}"
    end

    private

    def build_request(uri, body)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
      request
    end

    def perform_request(uri, request)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) do |http|
        http.request(request)
      end
    end

    def start_service
      raise ServiceError, "rubycrawl node service directory not found: #{@node_dir}" unless Dir.exist?(@node_dir)

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

      raise ServiceError, "rubycrawl node service failed to start within #{timeout}s. " \
                          "Check logs at #{@node_log || 'RUBYCRAWL_NODE_LOG'}"
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
  end
end
