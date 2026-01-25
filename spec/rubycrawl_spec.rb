# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyCrawl do
  it "returns a result object" do
    result = described_class.new.crawl("https://example.com")

    expect(result).to be_a(RubyCrawl::Result)
    expect(result.links).to be_a(Array)
    expect(result.metadata).to be_a(Hash)
  end
end
