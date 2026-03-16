# frozen_string_literal: true

namespace :rubycrawl do
  desc 'Check system dependencies and generate Rails initializer'
  task :install do
    require 'fileutils'

    # Ferrum manages Chrome automatically, but warn if not found in common locations
    chrome_found = %w[google-chrome chromium-browser chromium].any? do |cmd|
      system("which #{cmd}", out: File::NULL, err: File::NULL)
    end

    unless chrome_found
      warn '[rubycrawl] Chrome/Chromium not found in PATH. Ferrum will attempt to locate it automatically.'
      warn '[rubycrawl] macOS:  brew install --cask google-chrome'
      warn '[rubycrawl] Ubuntu: sudo apt-get install -y chromium-browser'
      warn '[rubycrawl] See README for Docker examples.'
    end

    if defined?(Rails)
      initializer_path = Rails.root.join('config', 'initializers', 'rubycrawl.rb')
      if File.exist?(initializer_path)
        puts "[rubycrawl] Initializer already exists at #{initializer_path}"
      else
        content = <<~RUBY
          # frozen_string_literal: true

          # RubyCrawl Configuration
          RubyCrawl.configure(
            # wait_until: "load",       # "load", "domcontentloaded", "networkidle"
            # block_resources: true,    # block images/fonts/CSS/media for speed
            # max_attempts: 3,          # retry count with exponential backoff
            # timeout: 30,             # browser navigation timeout in seconds
            # headless: true,          # set false to see the browser (debugging)
          )
        RUBY

        FileUtils.mkdir_p(File.dirname(initializer_path))
        File.write(initializer_path, content)
        puts "[rubycrawl] Created initializer at #{initializer_path}"
      end
    else
      puts '[rubycrawl] Rails not detected. Skipping initializer creation.'
    end
  end
end
