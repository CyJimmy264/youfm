# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::LogFile do
  it 'stores logs in an XDG-friendly state path by default' do
    Dir.mktmpdir do |tmpdir|
      original = ENV.fetch('XDG_STATE_HOME', nil)
      ENV['XDG_STATE_HOME'] = tmpdir

      expect(described_class.default_path).to eq(File.join(tmpdir, 'youfm', 'youfm.log'))
    ensure
      ENV['XDG_STATE_HOME'] = original
    end
  end

  it 'appends messages and returns the latest lines' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)

      3.times { |index| log_file.append("line #{index}\n") }

      expect(log_file.tail(lines: 2)).to eq(['line 1', 'line 2'])
    end
  end

  it 'returns latest lines from a large log file' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)

      File.open(path, 'wb') do |file|
        10_000.times { |index| file.write("line #{index}\n") }
      end

      expect(log_file.tail(lines: 3)).to eq(['line 9997', 'line 9998', 'line 9999'])
    end
  end

  it 'tees writes to the original stream and log file' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      target = StringIO.new
      log_file = described_class.new(path:)
      tee = described_class::Tee.new(target, log_file)

      tee.write("hello\n")
      tee.flush

      expect(target.string).to eq("hello\n")
      expect(log_file.tail(lines: 1)).to eq(['hello'])
    end
  end
end
