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

    it 'retries search without limit when Spotify says the limit is invalid' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      invalid_response = instance_double(
        Net::HTTPResponse,
        code: '400',
        body: JSON.dump('error' => { 'message' => 'Invalid limit' })
      )
      valid_response = instance_double(
        Net::HTTPResponse,
        code: '200',
        body: JSON.dump(
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
        )
      )
      http = instance_double(Net::HTTP)

      allow(http).to receive(:request).and_return(invalid_response, valid_response)
      allow(Net::HTTP).to receive(:start).twice.and_yield(http)

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

  describe 'rate limiting' do
    it 'raises a rate-limited error with Retry-After seconds from Spotify headers' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(
        Net::HTTPResponse,
        code: '429',
        body: JSON.dump('error' => { 'message' => 'Too many requests' })
      )
      allow(response).to receive(:[]).with('Retry-After').and_return('17')
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { client.queue }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError) do |error|
        expect(error.retry_after_seconds).to eq(17)
        expect(error.message).to eq('Too many requests')
      end
    end

    it 'blocks all follow-up Spotify requests until Retry-After expires' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      rate_limited_response = instance_double(
        Net::HTTPResponse,
        code: '429',
        body: JSON.dump('error' => { 'message' => 'Too many requests' })
      )
      success_response = instance_double(
        Net::HTTPResponse,
        code: '200',
        body: JSON.dump('devices' => [])
      )
      allow(rate_limited_response).to receive(:[]).with('Retry-After').and_return('17')
      allow(success_response).to receive(:[]).with('Retry-After').and_return(nil)

      now = Time.utc(2026, 4, 14, 10, 0, 0)
      allow(Time).to receive(:now).and_return(now)
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(rate_limited_response, success_response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { client.queue }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError)
      expect { client.available_devices }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError) do |error|
        expect(error.retry_after_seconds).to eq(17)
      end

      allow(Time).to receive(:now).and_return(now + 18)
      result = client.available_devices

      expect(result).to eq([])
      expect(Net::HTTP).to have_received(:start).twice
    end
  end

  describe 'timeouts' do
    it 'sets bounded HTTP timeouts and raises a Spotify timeout error' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      http = instance_double(Net::HTTP)

      allow(http).to receive(:request).and_raise(Net::ReadTimeout)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { client.available_devices }.to raise_error(
        YouFM::Services::SpotifyClient::TimeoutError,
        'Spotify request timed out'
      )
      expect(Net::HTTP).to have_received(:start).with(
        'api.spotify.test',
        443,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 10
      )
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
            'items' => { 'total' => 68 },
            'snapshot_id' => 'snapshot-1'
          }
        ]
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.current_user_playlists

      expect(result.length).to eq(1)
      expect(result.first.tracks_total).to eq(68)
      expect(result.first.snapshot_id).to eq('snapshot-1')
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

  describe '#playlist_tracks_page' do
    it 'returns one playlist page with has_more flag' do
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
          }
        ],
        'next' => 'https://api.spotify.test/v1/playlists/playlist-1/items?offset=100&limit=100'
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.playlist_tracks_page('playlist-1', limit: 100, offset: 0)

      expect(result[:has_more]).to be(true)
      expect(result[:tracks].map(&:display_label)).to eq(['Track - Artist'])
    end

    it 'uses cached playlist pages when snapshot id matches' do
      playlist_cache = instance_double(
        YouFM::Services::SpotifyPlaylistCache,
        fetch: {
          tracks: [
            {
              'id' => 'track-1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          ],
          has_more: false
        }
      )
      client = described_class.new(
        access_token: 'token',
        base_url: 'https://api.spotify.test/v1',
        playlist_cache: playlist_cache
      )

      result = client.playlist_tracks_page('playlist-1', limit: 100, offset: 0, snapshot_id: 'snapshot-1')

      expect(result[:has_more]).to be(false)
      expect(result[:tracks].map(&:display_label)).to eq(['Track - Artist'])
      expect(playlist_cache).to have_received(:fetch).with(
        playlist_id: 'playlist-1',
        snapshot_id: 'snapshot-1',
        offset: 0,
        limit: 100
      )
    end
  end

  describe '#cached_playlist_tracks_page' do
    it 'hydrates cached track payloads without touching the network' do
      playlist_cache = instance_double(
        YouFM::Services::SpotifyPlaylistCache,
        fetch: {
          tracks: [
            {
              'id' => 'track-1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          ],
          has_more: false
        }
      )
      client = described_class.new(
        access_token: 'token',
        base_url: 'https://api.spotify.test/v1',
        playlist_cache: playlist_cache
      )

      result = client.cached_playlist_tracks_page('playlist-1', limit: 100, offset: 0, snapshot_id: 'snapshot-1')

      expect(result[:tracks].map(&:display_label)).to eq(['Track - Artist'])
      expect(result[:has_more]).to be(false)
    end
  end

  describe '#cached_playlist_tracks' do
    it 'returns full cached playlist only when every page is present' do
      playlist_cache = instance_double(YouFM::Services::SpotifyPlaylistCache)
      allow(playlist_cache).to receive(:fetch).with(
        playlist_id: 'playlist-1',
        snapshot_id: 'snapshot-1',
        offset: 0,
        limit: 100
      ).and_return(
        {
          tracks: [
            {
              'id' => 'track-1',
              'name' => 'Track 1',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          ],
          has_more: true
        }
      )
      allow(playlist_cache).to receive(:fetch).with(
        playlist_id: 'playlist-1',
        snapshot_id: 'snapshot-1',
        offset: 100,
        limit: 100
      ).and_return(
        {
          tracks: [
            {
              'id' => 'track-2',
              'name' => 'Track 2',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:2',
              'duration_ms' => 123_000
            }
          ],
          has_more: false
        }
      )
      client = described_class.new(
        access_token: 'token',
        base_url: 'https://api.spotify.test/v1',
        playlist_cache: playlist_cache
      )

      result = client.cached_playlist_tracks('playlist-1', limit: 100, snapshot_id: 'snapshot-1')

      expect(result.map(&:display_label)).to eq(['Track 1 - Artist', 'Track 2 - Artist'])
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
