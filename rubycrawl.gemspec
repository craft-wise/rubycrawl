# frozen_string_literal: true

require_relative 'lib/rubycrawl/version'

Gem::Specification.new do |spec|
  spec.name = 'rubycrawl'
  spec.version = RubyCrawl::VERSION
  spec.authors = ['RubyCrawl contributors']
  spec.email = ['ganesh.navale@zohomail.in']

  spec.summary = 'Playwright-based web crawler for Ruby'
  spec.description = 'A Ruby-first web crawler that orchestrates a local Playwright service.'
  spec.homepage = 'https://github.com/craft-wise/rubycrawl'
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir.glob('{bin,lib,spec,node}/**/*', File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  spec.files += %w[README.md LICENSE Gemfile Rakefile rubycrawl.gemspec .rspec]

  spec.bindir = 'bin'
  spec.executables = []
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
