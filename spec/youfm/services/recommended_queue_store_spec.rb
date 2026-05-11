# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::RecommendedQueueStore do
  it 'persists and reloads recommended queue payload' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'recommended_queue.yml')
      store = described_class.new(path:)
      track = YouFM::Models::Track.new(
        id: 'track-1',
        title: 'Recommended',
        artists: ['Artist'],
        album: 'Album',
        uri: 'spotify:track:track-1',
        duration_ms: 123
      )

      store.save(
        track_ids: ['track-1'],
        tracks: [track],
        seeds: { 'track-1' => 'Seed — Artist (Взят из плейлиста: Daily)' }
      )

      payload = described_class.new(path:).load

      expect(payload[:track_ids]).to eq(['track-1'])
      expect(payload[:tracks]).to eq([
                                       {
                                         'id' => 'track-1',
                                         'name' => 'Recommended',
                                         'artists' => [{ 'name' => 'Artist' }],
                                         'album' => { 'name' => 'Album' },
                                         'uri' => 'spotify:track:track-1',
                                         'duration_ms' => 123
                                       }
                                     ])
      expect(payload[:seeds]).to eq('track-1' => 'Seed — Artist (Взят из плейлиста: Daily)')
    end
  end
end
