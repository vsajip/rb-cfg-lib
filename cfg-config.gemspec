require_relative 'lib/CFG/version'

Gem::Specification.new do |spec|
  spec.name = 'cfg-config'
  spec.version = CFG::VERSION
  spec.authors = ['Vinay Sajip']
  spec.email = ['vinay_sajip@yahoo.co.uk']

  spec.summary = 'A Ruby library for working with the CFG configuration format.'
  spec.description = 'A Ruby library for working with the CFG configuration format. \
See https://docs.red-dove.com/cfg/index.html for more information.'
  spec.homepage = 'https://docs.red-dove.com/cfg/index.html'
  spec.license  = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  # spec.metadata['source_code_uri'] = "TODO: Put your gem's public repo URL here."
  # spec.metadata['changelog_uri'] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir['README.md', 'LICENSE.txt',
                   'lib/**/*.rb', 'cfg-config.gemspec']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(/^exe\//) { |f| File.basename(f) }
  spec.require_paths = ['lib']
end
