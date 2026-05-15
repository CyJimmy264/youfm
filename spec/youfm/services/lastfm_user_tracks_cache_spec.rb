# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::LastfmUserTracksCache do
  it 'persists and reloads user track metadata within ttl' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'lastfm_user_tracks.yml')
      now = Time.utc(2026, 5, 15, 0, 0, 0)
      cache = described_class.new(path: path, clock: -> { now })

      cache.save('user.getLovedTracks', 'RJ', total_pages: 512, total_tracks: 5113)

      expect(cache.fetch('user.getLovedTracks', 'RJ', ttl: 24 * 60 * 60)).to eq(
        total_pages: 512,
        total_tracks: 5113
      )
    end
  end

  it 'expires user track metadata after ttl' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'lastfm_user_tracks.yml')
      now = Time.utc(2026, 5, 15, 0, 0, 0)
      cache = described_class.new(path: path, clock: -> { now })
      cache.save('user.getRecentTracks', 'RJ', total_pages: 3019, total_tracks: 30_183)

      expired_cache = described_class.new(path: path, clock: -> { now + (25 * 60 * 60) })

      expect(expired_cache.fetch('user.getRecentTracks', 'RJ', ttl: 24 * 60 * 60)).to be_nil
    end
  end
end
