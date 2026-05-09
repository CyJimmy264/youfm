# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::Logger do
  it 'writes timestamped info messages to stdout and log file' do
    allow(YouFM::Services::LogFile).to receive(:append_async)

    expect { described_class.info('[youfm] message') }.to output(
      /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\] \[youfm\] message\n\z/
    ).to_stdout
    expect(YouFM::Services::LogFile).to have_received(:append_async).with(
      /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\] \[youfm\] message\n\z/
    )
  end

  it 'writes timestamped warnings to stderr and log file' do
    allow(YouFM::Services::LogFile).to receive(:append_async)

    expect { described_class.warn('[youfm] warning') }.to output(
      /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\] \[youfm\] warning\n\z/
    ).to_stderr
    expect(YouFM::Services::LogFile).to have_received(:append_async).with(
      /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\] \[youfm\] warning\n\z/
    )
  end
end
