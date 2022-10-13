# frozen_string_literal: true

require_relative 'lib/bormashino_sequel_sqljs_adapter/version'

Gem::Specification.new do |spec|
  spec.name          = 'bormashino-sequel-sqljs-adapter'
  spec.version       = BormashinoSequelSqljsAdapter::VERSION
  spec.authors       = ['Kenichiro Yasuda']
  spec.email         = ['keyasuda@users.noreply.github.com']

  spec.summary       = 'SQL.JS adapter for Sequel'
  spec.description   = <<-DESCRIPTION
  SQL.JS adapter for Sequel on browser with Bormaŝino / ruby.wasm
  DESCRIPTION
  spec.homepage      = 'https://github.com/keyasuda/bormashino-sequel-sqljs-adapter'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0-preview1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir['lib/**/*.rb', 'lib/**/*.rake', 'LICENSE.txt', '*.md']
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency 'bormashino', '~> 0.1.9'

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata['rubygems_mfa_required'] = 'true'
end
