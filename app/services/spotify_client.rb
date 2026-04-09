# frozen_string_literal: true

module YouFM
  module Services
    class SpotifyClient
      class Error < StandardError; end
      class AuthenticationError < Error; end
      class PlaybackUnavailableError < Error; end
      class DeviceUnavailableError < Error; end

      def initialize(access_token:, base_url: 'https://api.spotify.com/v1', token_store: nil, authenticator: nil)
        @access_token = access_token.to_s.strip
        @base_url = base_url
        @token_store = token_store
        @authenticator = authenticator
      end

      def search_tracks(query, limit: 20)
        body = get('/search', q: query, type: 'track', limit: limit)
        items = body.fetch('tracks', {}).fetch('items', [])
        items.map { |item| build_track(item) }
      end

      def available_devices
        body = get('/me/player/devices')
        Array(body['devices']).map { |item| build_device(item) }
      end

      def current_playback
        body, code = get_with_code('/me/player')
        return Models::PlaybackState.new(device_name: nil, track: nil, playing: false, progress_ms: 0) if code == 204

        track = body['item'] ? build_track(body.fetch('item')) : nil
        Models::PlaybackState.new(
          device_name: body.dig('device', 'name'),
          track: track,
          playing: body.fetch('is_playing', false),
          progress_ms: body.fetch('progress_ms', 0)
        )
      end

      def queue
        body = get('/me/player/queue')
        Array(body['queue']).map { |item| build_track(item) }
      end

      def current_user_playlists(limit: 30)
        body = get('/me/playlists', limit: limit)
        Array(body['items']).map { |item| build_playlist(item) }
      end

      def playlist_tracks(playlist_id, limit: 100)
        all_items = []
        path = "/playlists/#{playlist_id}/items"
        params = { limit: limit }

        loop do
          body = get(path, params)
          all_items.concat(Array(body['items']))
          next_url = body['next']
          break if next_url.nil? || next_url.empty?

          path_and_query = next_url.sub(base_url, '')
          next_uri = URI.parse(path_and_query)
          path = next_uri.path
          params = URI.decode_www_form(next_uri.query).to_h
        end

        all_items.filter_map do |item|
          track_payload = item['item'] || item['track']
          next unless track_payload.is_a?(Hash)
          next if track_payload['type'].to_s == 'episode'

          build_track(track_payload)
        end
      end

      def play_track(track_uri)
        put('/me/player/play', { uris: [track_uri] })
      end

      def play_playlist(playlist_uri, device_id: nil)
        params = device_id ? { device_id: device_id } : {}
        put('/me/player/play', { context_uri: playlist_uri }, params:)
      end

      def transfer_playback(device_id, play: false)
        put('/me/player', { device_ids: [device_id], play: play })
      end

      def resume
        put('/me/player/play', {})
      end

      def pause
        put('/me/player/pause', {})
      end

      def connect!
        raise AuthenticationError, 'Spotify OAuth is not configured' unless authenticator

        authenticator.connect!
      end

      def disconnect!
        token_store&.clear
      end

      def connected?
        return true unless access_token.empty?

        !persisted_token['access_token'].to_s.empty?
      end

      def resumable_session?
        return true unless access_token.empty?

        !persisted_token['access_token'].to_s.empty? || (authenticator && !persisted_token['refresh_token'].to_s.empty?)
      end

      def configured?
        return true unless access_token.empty?

        resumable_session? || authenticator&.configured?
      end

      private

      attr_reader :access_token, :base_url, :token_store, :authenticator

      def build_track(item)
        Models::Track.new(
          id: item.fetch('id', ''),
          title: item.fetch('name', 'Unknown Track'),
          artists: Array(item['artists']).map { |artist| artist['name'] }.compact,
          album: item.dig('album', 'name').to_s,
          uri: item.fetch('uri', ''),
          duration_ms: item.fetch('duration_ms', 0)
        )
      end

      def build_device(item)
        Models::Device.new(
          id: item.fetch('id', ''),
          name: item.fetch('name', 'Unknown Device'),
          type: item.fetch('type', 'device'),
          active: item.fetch('is_active', false),
          restricted: item.fetch('is_restricted', false)
        )
      end

      def build_playlist(item)
        Models::Playlist.new(
          id: item.fetch('id', ''),
          name: item.fetch('name', 'Untitled Playlist'),
          uri: item.fetch('uri', ''),
          owner_name: item.dig('owner', 'display_name').to_s,
          tracks_total: playlist_items_total(item)
        )
      end

      def get(path, params = {})
        body, = get_with_code(path, params)
        body
      end

      def get_with_code(path, params = {})
        request(Net::HTTP::Get.new(build_uri(path, params)))
      end

      def put(path, payload, params: {})
        request(
          Net::HTTP::Put.new(build_uri(path, params)).tap do |request|
            request.body = JSON.dump(payload)
          end
        )
      end

      def build_uri(path, params = {})
        uri = URI.join(base_url.end_with?('/') ? base_url : "#{base_url}/", path.sub(%r{\A/}, ''))
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def request(request)
        ensure_token!
        response = perform_request(request, bearer_token)
        if response.code.to_i == 401 && refreshable?
          refreshed_token = refresh_bearer_token!
          response = perform_request(request, refreshed_token)
        end

        handle_response(response)
      end

      def handle_response(response)
        code = response.code.to_i
        body = response.body.to_s
        raise AuthenticationError, 'Spotify access token is missing or expired' if code == 401
        raise playback_error_for(code, body) if playback_error_for(code, body)
        raise Error, extract_error_message(body) if code >= 400 && code != 204

        return [{}, 204] if code == 204 || body.strip.empty?

        [JSON.parse(body), code]
      end

      def ensure_token!
        raise AuthenticationError, 'Spotify access token is missing' unless configured?
      end

      def bearer_token
        return access_token unless access_token.empty?

        refresh_bearer_token! if token_expired?
        persisted_token.fetch('access_token', '')
      end

      def refreshable?
        return false unless authenticator

        !persisted_token['refresh_token'].to_s.empty?
      end

      def refresh_bearer_token!
        raise AuthenticationError, 'Spotify refresh token is missing' unless refreshable?

        authenticator.refresh!(persisted_token.fetch('refresh_token'))
        persisted_token.fetch('access_token', '')
      end

      def token_expired?
        expires_at = persisted_token['expires_at'].to_s
        return false if expires_at.empty?

        Time.parse(expires_at) <= Time.now + 30
      rescue ArgumentError
        false
      end

      def persisted_token
        token_store ? token_store.load : {}
      end

      def perform_request(request, token)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'

        Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: request.uri.scheme == 'https') do |http|
          http.request(request)
        end
      end

      def playback_error_for(code, body)
        message = extract_error_message(body)
        return PlaybackUnavailableError.new(message) if code == 403
        return DeviceUnavailableError.new(message) if code == 404

        nil
      end

      def extract_error_message(body)
        parsed = JSON.parse(body)
        parsed.dig('error', 'message').to_s.strip.then { |message| message.empty? ? body : message }
      rescue JSON::ParserError
        body
      end

      def playlist_items_total(item)
        item.dig('items', 'total') || item.dig('tracks', 'total') || 0
      end
    end
  end
end
