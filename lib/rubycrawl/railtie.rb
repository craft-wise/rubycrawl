# frozen_string_literal: true

require "rails/railtie"

class RubyCrawl
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/install.rake", __dir__)
    end
  end
end
