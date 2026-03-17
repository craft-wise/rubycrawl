# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyCrawl::UrlNormalizer do
  describe '.normalize' do
    it 'returns nil for a completely invalid URL' do
      expect(described_class.normalize('not a url')).to be_nil
    end

    it 'returns nil for a relative URL with no base' do
      expect(described_class.normalize('/about')).to be_nil
    end

    it 'resolves relative URLs against a base' do
      expect(described_class.normalize('/about', 'https://example.com')).to eq('https://example.com/about')
    end

    it 'resolves relative paths against a base with path' do
      expect(described_class.normalize('page', 'https://example.com/blog/')).to eq('https://example.com/blog/page')
    end

    it 'lowercases scheme and host' do
      expect(described_class.normalize('HTTPS://Example.COM/path')).to eq('https://example.com/path')
    end

    it 'strips URL fragments' do
      expect(described_class.normalize('https://example.com/page#section')).to eq('https://example.com/page')
    end

    it 'removes trailing slash from paths (except root)' do
      expect(described_class.normalize('https://example.com/about/')).to eq('https://example.com/about')
    end

    it 'keeps root path as single slash' do
      expect(described_class.normalize('https://example.com/')).to eq('https://example.com/')
    end

    it 'keeps root path when no path given' do
      expect(described_class.normalize('https://example.com')).to eq('https://example.com/')
    end

    it 'removes utm_source tracking param' do
      result = described_class.normalize('https://example.com/?utm_source=google')
      expect(result).to eq('https://example.com/')
    end

    it 'removes all common tracking params' do
      url = 'https://example.com/page?utm_source=g&utm_medium=cpc&utm_campaign=x&utm_term=t&utm_content=c&fbclid=1&gclid=2'
      expect(described_class.normalize(url)).to eq('https://example.com/page')
    end

    it 'preserves non-tracking query params' do
      result = described_class.normalize('https://example.com/search?q=ruby&page=2')
      expect(result).to eq('https://example.com/search?page=2&q=ruby')
    end

    it 'sorts query params for stable comparison' do
      a = described_class.normalize('https://example.com/?z=1&a=2')
      b = described_class.normalize('https://example.com/?a=2&z=1')
      expect(a).to eq(b)
    end

    it 'keeps tracking params that are mixed with real params' do
      result = described_class.normalize('https://example.com/search?q=ruby&utm_source=google')
      expect(result).to eq('https://example.com/search?q=ruby')
    end

    it 'returns nil for a URI with no host' do
      expect(described_class.normalize('mailto:user@example.com')).to be_nil
    end
  end

  describe '.same_host?' do
    it 'returns true for identical hosts' do
      expect(described_class.same_host?('https://example.com/a', 'https://example.com/b')).to be true
    end

    it 'treats www and non-www as the same host' do
      expect(described_class.same_host?('https://www.example.com/', 'https://example.com/')).to be true
    end

    it 'returns false for different hosts' do
      expect(described_class.same_host?('https://other.com/', 'https://example.com/')).to be false
    end

    it 'is case-insensitive' do
      expect(described_class.same_host?('https://EXAMPLE.COM/', 'https://example.com/')).to be true
    end

    it 'returns false for an invalid URL' do
      expect(described_class.same_host?('not a url', 'https://example.com/')).to be false
    end
  end

  describe '.canonical_host' do
    it 'strips www prefix' do
      expect(described_class.canonical_host('www.example.com')).to eq('example.com')
    end

    it 'lowercases the host' do
      expect(described_class.canonical_host('EXAMPLE.COM')).to eq('example.com')
    end

    it 'returns nil for nil input' do
      expect(described_class.canonical_host(nil)).to be_nil
    end

    it 'does not strip subdomains other than www' do
      expect(described_class.canonical_host('api.example.com')).to eq('api.example.com')
    end
  end
end
