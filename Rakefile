# frozen_string_literal: true

require 'rake/testtask'

task default: :spec

desc 'Run RSpec'
task :spec do
  sh 'bundle exec rspec'
end

desc 'Run RuboCop'
task :rubocop do
  sh 'bundle exec rubocop'
end
