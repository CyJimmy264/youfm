# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::SpotifyPlaylistCache do
  it 'stores cached pages in an XDG-friendly cache path by default' do
    Dir.mktmpdir do |tmpdir|
      original = ENV['XDG_CACHE_HOME']
      ENV['XDG_CACHE_HOME'] = tmpdir

      cache = described_class.new
      cache.save(
        playlist_id: 'playlist-1',
        snapshot_id: 'snap-1',
        offset: 0,
        limit: 100,
        tracks: [{ 'id' => 'track-1' }],
        has_more: true
      )

      expect(File.exist?(File.join(tmpdir, 'youfm', 'spotify_playlist_pages.yml'))).to be(true)
    ensure
      ENV['XDG_CACHE_HOME'] = original
    end
  end

  it 'returns only pages matching the same snapshot id' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'spotify_playlist_pages.yml')
      cache = described_class.new(path:)
      cache.save(
        playlist_id: 'playlist-1',
        snapshot_id: 'snap-1',
        offset: 0,
        limit: 100,
        tracks: [{ 'id' => 'track-1' }],
        has_more: false
      )

      expect(cache.fetch(playlist_id: 'playlist-1', snapshot_id: 'snap-1', offset: 0, limit: 100)).to eq(
        { tracks: [{ 'id' => 'track-1' }], has_more: false }
      )
      expect(cache.fetch(playlist_id: 'playlist-1', snapshot_id: 'snap-2', offset: 0, limit: 100)).to be_nil
    end
  end

  it 'keeps previously saved pages for the same snapshot id' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'spotify_playlist_pages.yml')
      cache = described_class.new(path:)
      cache.save(
        playlist_id: 'playlist-1',
        snapshot_id: 'snap-1',
        offset: 0,
        limit: 100,
        tracks: [{ 'id' => 'track-1' }],
        has_more: true
      )
      cache.save(
        playlist_id: 'playlist-1',
        snapshot_id: 'snap-1',
        offset: 100,
        limit: 100,
        tracks: [{ 'id' => 'track-101' }],
        has_more: false
      )

      expect(cache.fetch(playlist_id: 'playlist-1', snapshot_id: 'snap-1', offset: 0, limit: 100)).to eq(
        { tracks: [{ 'id' => 'track-1' }], has_more: true }
      )
      expect(cache.fetch(playlist_id: 'playlist-1', snapshot_id: 'snap-1', offset: 100, limit: 100)).to eq(
        { tracks: [{ 'id' => 'track-101' }], has_more: false }
      )
    end
  end

  it 'serves repeated reads from in-memory store after the first load' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'spotify_playlist_pages.yml')
      described_class.new(path:).save(
        playlist_id: 'playlist-1',
        snapshot_id: 'snap-1',
        offset: 0,
        limit: 100,
        tracks: [{ 'id' => 'track-1' }],
        has_more: false
      )
      cache = described_class.new(path:)

      allow(YAML).to receive(:safe_load_file).and_call_original
      2.times { cache.fetch(playlist_id: 'playlist-1', snapshot_id: 'snap-1', offset: 0, limit: 100) }

      expect(YAML).to have_received(:safe_load_file).once
    end
  end
end
