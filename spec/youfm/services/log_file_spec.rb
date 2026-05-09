# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

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

  it 'normalizes glued timestamp-only leftovers from older log writes' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      File.write(
        path,
        '[2026-05-08T10:56:17+05:00] [youfm] status: Playback state updated' \
        "[2026-05-08T10:56:17+05:00] \n" \
        '[2026-05-08T10:56:17+05:00] [youfm] status: Spotify library updated' \
        "[2026-05-08T10:56:17+05:00] \n"
      )
      log_file = described_class.new(path:)

      expect(log_file.tail(lines: 10)).to eq(
        [
          '[2026-05-08T10:56:17+05:00] [youfm] status: Playback state updated',
          '[2026-05-08T10:56:17+05:00] [youfm] status: Spotify library updated'
        ]
      )
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

  it 'tees split puts writes as one log line' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      target = StringIO.new
      log_file = described_class.new(path:)
      tee = described_class::Tee.new(target, log_file)

      tee.write('hello')
      tee.write("\n")
      tee.flush

      expect(target.string).to eq("hello\n")
      expect(log_file.tail(lines: 2)).to eq(['hello'])
    end
  end

  it 'does not log blank lines from standalone newline writes' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)

      log_file.append("\n")

      expect(log_file.tail(lines: 1)).to eq([])
    end
  end

  it 'publishes async writes to recent lines before file persistence catches up' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)
      allow(log_file).to receive(:append_to_file) { sleep 0.05 }
      initial_revision = log_file.revision

      log_file.append_async("async line\n")

      expect(log_file.tail(lines: 1)).to eq(['async line'])
      expect(log_file.revision).to be > initial_revision
      log_file.flush
    end
  end

  it 'serves recent appended lines from memory before reading the file' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)

      log_file.append("current line\n")
      File.write(path, "older file line\n")

      expect(log_file.tail(lines: 50)).to eq(['current line'])
    end
  end

  it 'keeps file-backed tail lines in memory before appending new lines' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)
      File.write(path, "older file line\n")

      expect(log_file.tail(lines: 50)).to eq(['older file line'])

      log_file.append("current line\n")

      expect(log_file.tail(lines: 50)).to eq(['older file line', 'current line'])
    end
  end

  it 'seeds recent lines from an existing log file on initialization' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      File.write(path, "older file line\n")
      log_file = described_class.new(path:)

      log_file.append("current line\n")

      expect(log_file.tail(lines: 50)).to eq(['older file line', 'current line'])
    end
  end

  it 'notifies waiters when recent lines change' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'youfm.log')
      log_file = described_class.new(path:)
      initial_revision = log_file.revision
      observed_revision = Queue.new

      waiter = Thread.new { observed_revision << log_file.wait_for_revision(initial_revision, timeout: 1) }
      log_file.append("current line\n")

      expect(observed_revision.pop(timeout: 1)).to be > initial_revision
      waiter.join
    end
  end
end
