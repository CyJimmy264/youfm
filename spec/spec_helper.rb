# frozen_string_literal: true

require 'simplecov'
require 'stringio'

SimpleCov.start do
  add_filter '/spec/'
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'youfm'
YouFM::Application.loader.setup

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.after(:suite) do
    next unless QApplication.instance_exists

    QApplication.close_all_windows
    QApplication.process_events
    qt_app = YouFM::Application.instance_variable_get(:@qt_app)
    qt_app.dispose if qt_app && !qt_app.class.name.to_s.start_with?('RSpec::')
    YouFM::Application.instance_variable_set(:@qt_app, nil)
  end

  config.before do |example|
    allow(YouFM::Services::LogFile).to receive(:append_async) unless example.metadata[:real_log_file]
  end

  config.around do |example|
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    example.run
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end
