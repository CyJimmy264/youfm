# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::SpotifyErrorLog do
  it 'appends JSON lines with timestamp, context and payload' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'spotify_errors.jsonl')
      now = Time.utc(2026, 5, 15, 12, 0, 0)
      log = described_class.new(path: path, clock: -> { now })

      log.append(
        event: :missing_track_uri,
        context: 'search query="Song"',
        payload: { 'id' => '123', 'uri' => nil }
      )

      entry = JSON.parse(File.read(path))
      expect(entry).to eq(
        'timestamp' => '2026-05-15T12:00:00Z',
        'event' => 'missing_track_uri',
        'context' => 'search query="Song"',
        'payload' => { 'id' => '123', 'uri' => nil }
      )
    end
  end
end
