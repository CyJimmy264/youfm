# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::LastfmTopTracksCache do
  it 'stores cache data in an XDG-friendly cache path by default' do
    Dir.mktmpdir do |tmpdir|
      original = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = tmpdir

      cache = described_class.new
      cache.save('Air', period: '12month', limit: 20, tracks: [{ 'name' => 'La femme d’argent' }])

      expect(File.exist?(File.join(tmpdir, 'youfm', 'lastfm_top_tracks.yml'))).to be(true)
    ensure
      ENV['XDG_CACHE_HOME'] = original
    end
  end

  it 'returns cached tracks until the daily ttl expires' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'lastfm_top_tracks.yml')
      now = Time.utc(2026, 4, 10, 12, 0, 0)
      clock = -> { now }
      cache = described_class.new(path:, clock:)

      cache.save('Air', period: '12month', limit: 20, tracks: [{ 'name' => 'La femme d’argent' }])
      expect(cache.fetch('Air', period: '12month', limit: 20, ttl: 24 * 60 * 60)).to eq(
        [{ 'name' => 'La femme d’argent' }]
      )

      now += (24 * 60 * 60) + 1
      expect(cache.fetch('Air', period: '12month', limit: 20, ttl: 24 * 60 * 60)).to be_nil
    end
  end
end
