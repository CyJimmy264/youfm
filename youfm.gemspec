# frozen_string_literal: true

require_relative 'lib/youfm/version'

Gem::Specification.new do |spec|
  spec.name = 'youfm'
  spec.version = YouFM::VERSION
  spec.authors = ['Maksim Veynberg']
  spec.email = ['mv@cj264.ru']

  spec.summary = 'Desktop music player for Spotify built with Ruby and Qt'
  spec.description = 'MVVM Ruby desktop music player with Qt UI and Spotify-first source abstraction.'
  spec.homepage = 'https://github.com/CyJimmy264/youfm'
  spec.license = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir[
    'app/**/*',
    'bin/*',
    'config/**/*',
    'lib/**/*.rb',
    'README.md',
    'Rakefile'
  ]

  spec.bindir = 'bin'
  spec.executables = ['youfm']
  spec.require_paths = ['lib']

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'dotenv', '~> 3.1'
  spec.add_dependency 'qt', '~> 0.1', '>= 0.1.7'
  spec.add_dependency 'zeitwerk', '~> 2.6'
end
