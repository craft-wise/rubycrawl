# frozen_string_literal: true

require 'bundler/setup'
require 'rubycrawl'

# On Linux CI, Chrome requires --no-sandbox. Set BROWSER_NO_SANDBOX=1 in the workflow.
RubyCrawl.configure(browser_options: { 'no-sandbox': nil }, timeout: 60) if ENV['BROWSER_NO_SANDBOX']

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
