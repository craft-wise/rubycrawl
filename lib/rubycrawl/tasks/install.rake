# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :rubycrawl do
  desc 'Install Node dependencies and create initializer'
  task :install do
    require 'fileutils'

    gem_root = File.expand_path('../../../', __dir__)
    node_dir = File.join(gem_root, 'node')

    abort("rubycrawl: node directory not found at #{node_dir}") unless Dir.exist?(node_dir)

    Dir.chdir(node_dir) do
      puts('[rubycrawl] Installing Node dependencies...')
      system('npm', 'install') || abort('rubycrawl: npm install failed')

      puts('[rubycrawl] Installing Playwright browsers...')
      system('npx', 'playwright', 'install') || abort('rubycrawl: playwright install failed')
    end

    if defined?(Rails)
      initializer_path = Rails.root.join('config', 'initializers', 'rubycrawl.rb')
      if File.exist?(initializer_path)
        puts("[rubycrawl] Initializer already exists at #{initializer_path}")
      else
        content = <<~RUBY
          # frozen_string_literal: true

          # rubycrawl default configuration (uncomment to customize)
          #
          # RubyCrawl.configure(
          #   wait_until: "load",        # load | domcontentloaded | networkidle
          #   block_resources: true       # true/false
          # )
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
