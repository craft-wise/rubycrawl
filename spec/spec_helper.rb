# frozen_string_literal: true

require 'bundler/setup'
require 'rubycrawl'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Integration tests require a live Chrome browser and network.
  # Run them explicitly with: INTEGRATION=1 bundle exec rspec
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
end
