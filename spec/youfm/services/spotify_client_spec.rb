# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::SpotifyClient do
  def spotify_client(http_client:, **options)
    described_class.new(
      access_token: 'token',
      base_url: 'https://api.spotify.test/v1',
      http_client: http_client,
      **options
    )
  end

  def http_client_with(*responses)
    instance_double(YouFM::Services::PersistentHttpClient).tap do |http_client|
      allow(http_client).to receive(:request).and_return(*responses)
    end
  end

  def http_response(code:, body:, headers: {})
    instance_double(YouFM::Services::PersistentHttpClient::Response, code: code, body: body).tap do |response|
      allow(response).to receive(:[]).and_return(nil)
      headers.each do |key, value|
        allow(response).to receive(:[]).with(key).and_return(value)
      end
    end
  end

  describe '#search_tracks' do
    it 'maps Spotify track payloads into track models' do
      response = http_response(code: '200', body: JSON.dump(
        'tracks' => {
          'items' => [
            {
              'id' => '1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000,
              'explicit' => true
            }
          ]
        }
      ))
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.search_tracks('track')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
      expect(result.first.explicit).to be(true)
    end

    it 'retries search without limit when Spotify says the limit is invalid' do
      invalid_response = http_response(
        code: '400',
        body: JSON.dump('error' => { 'message' => 'Invalid limit' })
      )
      valid_response = http_response(
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
      http_client = http_client_with(invalid_response, valid_response)
      client = spotify_client(http_client: http_client)

      result = client.search_tracks('track')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
    end

    it 'normalizes nil uri values into empty strings' do
      allow(YouFM::Services::SpotifyErrorLog).to receive(:append)
      allow(YouFM::Services::Logger).to receive(:warn)
      response = http_response(code: '200', body: JSON.dump(
        'tracks' => {
          'items' => [
            {
              'id' => '1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => nil,
              'duration_ms' => 123_000
            }
          ]
        }
      ))
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.search_tracks('track')

      expect(result.first.uri).to eq('')
      expect(YouFM::Services::SpotifyErrorLog).to have_received(:append).with(
        event: :missing_track_uri,
        context: 'search query="track"',
        payload: hash_including('id' => '1', 'name' => 'Track', 'uri' => nil)
      )
    end
  end

  describe '#current_playback' do
    it 'returns an empty playback state on 204' do
      response = http_response(code: '204', body: '')
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      playback = client.current_playback

      expect(playback.track).to be_nil
      expect(playback.playing).to be(false)
    end
  end

  describe 'rate limiting' do
    it 'raises a rate-limited error with Retry-After seconds from Spotify headers' do
      response = http_response(
        code: '429',
        body: JSON.dump('error' => { 'message' => 'Too many requests' }),
        headers: { 'Retry-After' => '17' }
      )
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      expect { client.queue }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError) do |error|
        expect(error.retry_after_seconds).to eq(17)
        expect(error.message).to eq('Too many requests')
      end
    end

    it 'blocks all follow-up Spotify requests until Retry-After expires' do
      rate_limited_response = http_response(
        code: '429',
        body: JSON.dump('error' => { 'message' => 'Too many requests' }),
        headers: { 'Retry-After' => '17' }
      )
      success_response = http_response(
        code: '200',
        body: JSON.dump('devices' => [])
      )

      now = Time.utc(2026, 4, 14, 10, 0, 0)
      allow(Time).to receive(:now).and_return(now)
      http_client = http_client_with(rate_limited_response, success_response)
      client = spotify_client(http_client: http_client)

      expect { client.queue }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError)
      expect { client.available_devices }.to raise_error(YouFM::Services::SpotifyClient::RateLimitedError) do |error|
        expect(error.retry_after_seconds).to eq(17)
      end

      allow(Time).to receive(:now).and_return(now + 18)
      result = client.available_devices

      expect(result).to eq([])
      expect(http_client).to have_received(:request).twice
    end
  end

  describe 'timeouts' do
    it 'raises a Spotify timeout error' do
      http_client = instance_double(YouFM::Services::PersistentHttpClient)

      allow(http_client).to receive(:request).and_raise(HTTPX::TimeoutError.new(1, 'timeout'))
      client = spotify_client(http_client: http_client)

      expect { client.available_devices }.to raise_error(
        YouFM::Services::SpotifyClient::TimeoutError,
        'Spotify request timed out'
      )
    end
  end

  describe '#available_devices' do
    it 'maps Spotify devices into device models' do
      response = http_response(code: '200', body: JSON.dump(
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
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.available_devices

      expect(result.length).to eq(1)
      expect(result.first.display_label).to include('MacBook')
    end
  end

  describe '#play_track' do
    it 'keeps player 403 errors as playback unavailable errors' do
      response = http_response(
        code: '403',
        body: JSON.dump('error' => { 'message' => 'Premium required' })
      )
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      expect { client.play_track('spotify:track:1') }.to raise_error(
        YouFM::Services::SpotifyClient::PlaybackUnavailableError,
        'Premium required'
      )
    end

    it 'rejects tracks without uri before calling Spotify' do
      http_client = instance_double(YouFM::Services::PersistentHttpClient)
      allow(http_client).to receive(:request)
      client = spotify_client(http_client: http_client)

      expect { client.play_track('') }.to raise_error(
        YouFM::Services::SpotifyClient::InvalidTrackError,
        'Spotify track URI is missing'
      )
      expect(http_client).not_to have_received(:request)
    end
  end

  describe '#add_to_queue' do
    it 'rejects tracks without uri before calling Spotify' do
      http_client = instance_double(YouFM::Services::PersistentHttpClient)
      allow(http_client).to receive(:request)
      client = spotify_client(http_client: http_client)

      expect { client.add_to_queue('') }.to raise_error(
        YouFM::Services::SpotifyClient::InvalidTrackError,
        'Spotify track URI is missing'
      )
      expect(http_client).not_to have_received(:request)
    end
  end

  describe '#current_user_playlists' do
    it 'uses items.total when Spotify returns the new playlist shape' do
      response = http_response(code: '200', body: JSON.dump(
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
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.current_user_playlists

      expect(result.length).to eq(1)
      expect(result.first.tracks_total).to eq(68)
      expect(result.first.snapshot_id).to eq('snapshot-1')
    end
  end

  describe '#playlist_tracks' do
    it 'maps playlist track items and skips episodes' do
      response = http_response(code: '200', body: JSON.dump(
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
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.playlist_tracks('playlist-1')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
    end
  end

  describe '#playlist_tracks_page' do
    it 'returns one playlist page with has_more flag' do
      response = http_response(code: '200', body: JSON.dump(
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
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      result = client.playlist_tracks_page('playlist-1', limit: 100, offset: 0)

      expect(result[:has_more]).to be(true)
      expect(result[:tracks].map(&:display_label)).to eq(['Track - Artist'])
      expect(http_client).to have_received(:request) do |request|
        expect(URI.decode_www_form(request.uri.query).to_h).to include(
          'fields' => YouFM::Services::SpotifyClient::PLAYLIST_TRACK_FIELDS
        )
      end
    end

    it 'keeps playlist item 403 errors as generic Spotify errors' do
      response = http_response(
        code: '403',
        body: JSON.dump('error' => { 'message' => 'Insufficient client scope' })
      )
      http_client = http_client_with(response)
      client = spotify_client(http_client: http_client)

      expect { client.playlist_tracks_page('playlist-1', limit: 100, offset: 0) }.to raise_error(
        YouFM::Services::SpotifyClient::Error,
        'Insufficient client scope'
      )
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
    it 'returns all contiguous cached playlist pages' do
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

    it 'returns partial cached playlist when later pages are missing' do
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
      ).and_return(nil)
      client = described_class.new(
        access_token: 'token',
        base_url: 'https://api.spotify.test/v1',
        playlist_cache: playlist_cache
      )

      result = client.cached_playlist_tracks('playlist-1', limit: 100, snapshot_id: 'snapshot-1')

      expect(result.map(&:display_label)).to eq(['Track 1 - Artist'])
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
