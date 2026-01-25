# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :rubycrawl do
  desc 'Install Node dependencies and create initializer'
  task :install do
    require 'fileutils'

    # Check Node.js is installed
    unless system('node', '--version', out: File::NULL, err: File::NULL)
      abort <<~MSG
        [rubycrawl] ERROR: Node.js is not installed or not in PATH.

        RubyCrawl requires Node.js (v18+ recommended) for browser automation.

        Install Node.js:
          - macOS:   brew install node
          - Ubuntu:  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
          - Windows: https://nodejs.org/en/download/

        After installing, run this task again:
          bundle exec rake rubycrawl:install
      MSG
    end

    gem_root = File.expand_path('../../../', __dir__)
    node_dir = File.join(gem_root, 'node')

    abort("[rubycrawl] ERROR: node directory not found at #{node_dir}") unless Dir.exist?(node_dir)

    Dir.chdir(node_dir) do
      puts('[rubycrawl] Installing Node dependencies...')
      system('npm', 'install') || abort('[rubycrawl] ERROR: npm install failed')

      puts('[rubycrawl] Installing Playwright browsers...')
      system('npx', 'playwright', 'install') || abort('[rubycrawl] ERROR: playwright install failed')
    end

    if defined?(Rails)
      initializer_path = Rails.root.join('config', 'initializers', 'rubycrawl.rb')
      if File.exist?(initializer_path)
        puts("[rubycrawl] Initializer already exists at #{initializer_path}")
      else
        content = <<~RUBY
          # frozen_string_literal: true

          # RubyCrawl Configuration
          # =======================
          # Uncomment and modify options as needed.

          RubyCrawl.configure(
            # wait_until - Page load strategy:
            #   "load"             - Wait for load event (fastest, good for static sites)
            #   "domcontentloaded" - Wait for DOM ready (medium speed)
            #   "networkidle"      - Wait until no network requests for 500ms (best for SPAs)
            # wait_until: "load",

            # Block images, fonts, CSS, media for faster crawls (2-3x speedup)
            # block_resources: true,

            # Maximum retry attempts for transient failures (with exponential backoff)
            # max_retries: 3,

            # Node service settings (usually no need to change)
            # host: "127.0.0.1",
            # port: 3344,

            # Custom Node.js binary path (if not in PATH)
            # node_bin: "/usr/local/bin/node",

            # Log file for Node service output (useful for debugging)
            # node_log: Rails.root.join("log", "rubycrawl.log").to_s
          )
        RUBY

        FileUtils.mkdir_p(File.dirname(initializer_path))
        File.write(initializer_path, content)
        puts("[rubycrawl] Created initializer at #{initializer_path}")
      end
    else
      puts('[rubycrawl] Rails not detected. Skipping initializer creation.')
    end
  end
end
# rubocop:enable Metrics/BlockLength
