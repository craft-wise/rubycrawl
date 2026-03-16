# frozen_string_literal: true

require_relative 'lib/rubycrawl/version'

Gem::Specification.new do |spec|
  spec.name = 'rubycrawl'
  spec.version = RubyCrawl::VERSION
  spec.authors = ['RubyCrawl contributors']
  spec.email = ['ganesh.navale@zohomail.in']

  spec.summary = 'Pure Ruby web crawler with full JavaScript rendering'
  spec.description = 'rubycrawl uses Ferrum (Chrome DevTools Protocol) for JS rendering.'
  spec.homepage = 'https://github.com/craft-wise/rubycrawl'
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.0'

  spec.files  = Dir.glob('{lib}/**/*', File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  spec.files += %w[README.md LICENSE Rakefile rubycrawl.gemspec .rspec]

  spec.bindir = 'bin'
  spec.executables = []
  spec.require_paths = ['lib']

  spec.add_dependency 'ferrum',           '~> 0.15'
  spec.add_dependency 'reverse_markdown', '~> 2.1'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
