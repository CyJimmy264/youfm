# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::SpotifyClient do
  describe '#search_tracks' do
    it 'maps Spotify track payloads into track models' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '200', body: JSON.dump(
        'tracks' => {
          'items' => [
            {
              'id' => '1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          ]
        }
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.search_tracks('track')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
    end
  end

  describe '#current_playback' do
    it 'returns an empty playback state on 204' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '204', body: '')
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      playback = client.current_playback

      expect(playback.track).to be_nil
      expect(playback.playing).to be(false)
    end
  end

  describe '#available_devices' do
    it 'maps Spotify devices into device models' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '200', body: JSON.dump(
        'devices' => [
          {
            'id' => 'device-1',
            'name' => 'MacBook',
            'type' => 'Computer',
            'is_active' => true,
            'is_restricted' => false
          }
        ]
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.available_devices

      expect(result.length).to eq(1)
      expect(result.first.display_label).to include('MacBook')
    end
  end

  describe '#current_user_playlists' do
    it 'uses items.total when Spotify returns the new playlist shape' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '200', body: JSON.dump(
        'items' => [
          {
            'id' => 'playlist-1',
            'name' => 'My Playlist',
            'uri' => 'spotify:playlist:1',
            'owner' => { 'display_name' => 'Owner' },
            'items' => { 'total' => 68 }
          }
        ]
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.current_user_playlists

      expect(result.length).to eq(1)
      expect(result.first.tracks_total).to eq(68)
    end
  end

  describe '#playlist_tracks' do
    it 'maps playlist track items and skips episodes' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '200', body: JSON.dump(
        'items' => [
          {
            'item' => {
              'id' => 'track-1',
              'type' => 'track',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          },
          {
            'item' => {
              'id' => 'episode-1',
              'type' => 'episode',
              'name' => 'Episode'
            }
          }
        ]
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.playlist_tracks('playlist-1')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
    end
  end

  describe '#disconnect!' do
    it 'clears persisted token store' do
      token_store = instance_double(YouFM::Services::SpotifyTokenStore, clear: true)
      client = described_class.new(access_token: '', base_url: 'https://api.spotify.test/v1', token_store: token_store)

      client.disconnect!

      expect(token_store).to have_received(:clear)
    end
  end

  describe '#resumable_session?' do
    it 'returns true when a refresh token is stored' do
      token_store = instance_double(YouFM::Services::SpotifyTokenStore, load: { 'refresh_token' => 'refresh-token' })
      authenticator = instance_double(YouFM::Services::SpotifyAuthenticator)
      client = described_class.new(
        access_token: '',
        base_url: 'https://api.spotify.test/v1',
        token_store: token_store,
        authenticator: authenticator
      )

      expect(client.resumable_session?).to be(true)
    end
  end
end
