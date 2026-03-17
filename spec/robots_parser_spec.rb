# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyCrawl::RobotsParser do
  # Build a parser directly from content string (no network).
  def parser(content)
    described_class.new(content)
  end

  describe '#allowed?' do
    it 'allows everything when robots.txt is empty' do
      expect(parser('').allowed?('https://example.com/anything')).to be true
    end

    it 'disallows a path matching a Disallow rule' do
      content = "User-agent: *\nDisallow: /private"
      expect(parser(content).allowed?('https://example.com/private')).to be false
      expect(parser(content).allowed?('https://example.com/private/page')).to be false
    end

    it 'allows paths that do not match any Disallow rule' do
      content = "User-agent: *\nDisallow: /private"
      expect(parser(content).allowed?('https://example.com/public')).to be true
    end

    it 'disallows everything when Disallow: /' do
      content = "User-agent: *\nDisallow: /"
      expect(parser(content).allowed?('https://example.com/')).to be false
      expect(parser(content).allowed?('https://example.com/page')).to be false
    end

    it 'allows everything when Disallow is empty' do
      content = "User-agent: *\nDisallow:"
      expect(parser(content).allowed?('https://example.com/page')).to be true
    end

    it 'Allow rule takes precedence over Disallow' do
      content = "User-agent: *\nDisallow: /private\nAllow: /private/ok"
      expect(parser(content).allowed?('https://example.com/private/ok')).to be true
      expect(parser(content).allowed?('https://example.com/private/secret')).to be false
    end

    it 'ignores rules for specific user agents' do
      content = "User-agent: Googlebot\nDisallow: /secret\n\nUser-agent: *\nDisallow: /blocked"
      expect(parser(content).allowed?('https://example.com/secret')).to be true
      expect(parser(content).allowed?('https://example.com/blocked')).to be false
    end

    it 'supports * wildcard in rules' do
      content = "User-agent: *\nDisallow: /api/*.json"
      expect(parser(content).allowed?('https://example.com/api/data.json')).to be false
      expect(parser(content).allowed?('https://example.com/api/data.xml')).to be true
    end

    it 'supports $ end-of-string anchor in rules' do
      content = "User-agent: *\nDisallow: /page$"
      expect(parser(content).allowed?('https://example.com/page')).to be false
      expect(parser(content).allowed?('https://example.com/page/sub')).to be true
    end

    it 'strips inline comments' do
      content = "User-agent: * # all bots\nDisallow: /secret # keep out"
      expect(parser(content).allowed?('https://example.com/secret')).to be false
    end

    it 'returns true for an invalid URL' do
      content = "User-agent: *\nDisallow: /"
      expect(parser(content).allowed?('not a url')).to be true
    end
  end

  describe '#crawl_delay' do
    it 'returns nil when Crawl-delay is not specified' do
      expect(parser('').crawl_delay).to be_nil
    end

    it 'returns the delay as a Float' do
      content = "User-agent: *\nCrawl-delay: 2"
      expect(parser(content).crawl_delay).to eq(2.0)
    end

    it 'returns fractional delay' do
      content = "User-agent: *\nCrawl-delay: 0.5"
      expect(parser(content).crawl_delay).to eq(0.5)
    end

    it 'ignores Crawl-delay for other user agents' do
      content = "User-agent: Googlebot\nCrawl-delay: 10\n\nUser-agent: *\nDisallow:"
      expect(parser(content).crawl_delay).to be_nil
    end
  end

  describe '.fetch' do
    it 'returns a permissive parser on network error' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
      result = described_class.fetch('https://example.com')
      expect(result.allowed?('https://example.com/anything')).to be true
    end

    it 'returns a permissive parser when robots.txt returns non-200' do
      response = instance_double(Net::HTTPNotFound, is_a?: false)
      allow(Net::HTTP).to receive(:start).and_yield(
        instance_double(Net::HTTP, get: response)
      )
      result = described_class.fetch('https://example.com')
      expect(result.allowed?('https://example.com/anything')).to be true
    end

    it 'parses content from a 200 response' do
      body = "User-agent: *\nDisallow: /secret"
      response = instance_double(Net::HTTPOK, body: body)
      allow(response).to receive(:is_a?).with(Net::HTTPOK).and_return(true)
      http = instance_double(Net::HTTP, get: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = described_class.fetch('https://example.com')
      expect(result.allowed?('https://example.com/secret')).to be false
    end
  end
end
