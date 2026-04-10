# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::LastfmSimilarArtistsCache do
  it 'stores cache data in an XDG-friendly cache path by default' do
    Dir.mktmpdir do |tmpdir|
      original = ENV['XDG_CACHE_HOME']
      ENV['XDG_CACHE_HOME'] = tmpdir

      cache = described_class.new
      cache.save('Air', [{ 'name' => 'Phoenix', 'match' => '0.8' }])

      expect(File.exist?(File.join(tmpdir, 'youfm', 'lastfm_similar_artists.yml'))).to be(true)
    ensure
      ENV['XDG_CACHE_HOME'] = original
    end
  end

  it 'returns cached artists until the weekly ttl expires' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'lastfm_similar_artists.yml')
      now = Time.utc(2026, 4, 10, 12, 0, 0)
      clock = -> { now }
      cache = described_class.new(path:, clock:)

      cache.save('Air', [{ 'name' => 'Phoenix', 'match' => '0.8' }])
      expect(cache.fetch('Air', ttl: 7 * 24 * 60 * 60)).to eq([{ 'name' => 'Phoenix', 'match' => '0.8' }])

      now += 7 * 24 * 60 * 60 + 1
      expect(cache.fetch('Air', ttl: 7 * 24 * 60 * 60)).to be_nil
    end
  end
end
