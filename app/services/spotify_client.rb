# frozen_string_literal: true

module YouFM
  module Services
    class SpotifyClient
      class Error < StandardError; end
      class AuthenticationError < Error; end

      def initialize(access_token:, base_url: 'https://api.spotify.com/v1')
        @access_token = access_token.to_s.strip
        @base_url = base_url
      end

      def search_tracks(query, limit: 20)
        body = get('/search', q: query, type: 'track', limit: limit)
        items = body.fetch('tracks', {}).fetch('items', [])
        items.map { |item| build_track(item) }
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

      def play_track(track_uri)
        put('/me/player/play', { uris: [track_uri] })
      end

      def resume
        put('/me/player/play', {})
      end

      def pause
        put('/me/player/pause', {})
      end

      def configured?
        !access_token.empty?
      end

      private

      attr_reader :access_token, :base_url

      def build_track(item)
        Models::Track.new(
          id: item.fetch('id'),
          title: item.fetch('name'),
          artists: Array(item['artists']).map { |artist| artist['name'] }.compact,
          album: item.dig('album', 'name').to_s,
          uri: item.fetch('uri'),
          duration_ms: item.fetch('duration_ms', 0)
        )
      end

      def get(path, params = {})
        body, = get_with_code(path, params)
        body
      end

      def get_with_code(path, params = {})
        request(Net::HTTP::Get.new(build_uri(path, params)))
      end

      def put(path, payload)
        request(
          Net::HTTP::Put.new(build_uri(path)).tap do |request|
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
        request['Authorization'] = "Bearer #{access_token}"
        request['Content-Type'] = 'application/json'

        response = Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: request.uri.scheme == 'https') do |http|
          http.request(request)
        end

        handle_response(response)
      end

      def handle_response(response)
        code = response.code.to_i
        raise AuthenticationError, 'Spotify access token is missing' if code == 401
        raise Error, response.body.to_s if code >= 400 && code != 204

        return [{}, 204] if code == 204 || response.body.to_s.strip.empty?

        [JSON.parse(response.body), code]
      end

      def ensure_token!
        raise AuthenticationError, 'Spotify access token is missing' unless configured?
      end
    end
  end
end
