# frozen_string_literal: true

module YouFM
  module Services
    class SpotifyClient
      PLAYLIST_TRACK_FIELDS = 'items(item(id,type,name,artists(name),album(name),uri,duration_ms)),next'
      class Error < StandardError; end
      class AuthenticationError < Error; end
      class PlaybackUnavailableError < Error; end
      class DeviceUnavailableError < Error; end
      class TimeoutError < Error; end
      class RateLimitedError < Error
        attr_reader :retry_after_seconds

        def initialize(message, retry_after_seconds: nil)
          super(message)
          @retry_after_seconds = retry_after_seconds
        end
      end

      def initialize(access_token:, base_url: 'https://api.spotify.com/v1', token_store: nil, authenticator: nil, playlist_cache: nil)
        @access_token = access_token.to_s.strip
        @base_url = base_url
        @token_store = token_store
        @authenticator = authenticator
        @playlist_cache = playlist_cache
        @rate_limited_until = nil
      end

      def search_tracks(query, limit: 20)
        search_limit = normalize_search_limit(limit)
        body = search_tracks_body(query, limit: search_limit)
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
        currently_playing_id = body.dig('currently_playing', 'id')
        queue_items = Array(body['queue']).reject { |item| item['id'] == currently_playing_id }
        tracks = queue_items.map { |item| build_track(item) }
        tracks.uniq(&:id)
      end

      def current_user_playlists(limit: 30)
        body = get('/me/playlists', limit: limit)
        Array(body['items']).map { |item| build_playlist(item) }
      end

      def playlist_tracks(playlist_id, limit: 100, snapshot_id: nil)
        tracks = []
        offset = 0

        loop do
          page = playlist_tracks_page(playlist_id, limit:, offset:, snapshot_id:)
          tracks.concat(page[:tracks])
          break unless page[:has_more]

          offset += limit
        end

        tracks
      end

      def playlist_tracks_page(playlist_id, limit: 100, offset: 0, snapshot_id: nil)
        cached_page = cached_playlist_tracks_page(playlist_id, limit:, offset:, snapshot_id:)
        if cached_page
          puts "[youfm] spotify playlist page cache hit: playlist_id=#{playlist_id} snapshot_id=#{snapshot_id || 'none'} offset=#{offset} limit=#{limit}"
          return cached_page
        end

        puts "[youfm] spotify playlist page cache miss: playlist_id=#{playlist_id} snapshot_id=#{snapshot_id || 'none'} offset=#{offset} limit=#{limit}"

        started_at = Time.now
        body = get(
          "/playlists/#{playlist_id}/items",
          { limit: limit, offset: offset, fields: PLAYLIST_TRACK_FIELDS }
        )
        elapsed = Time.now - started_at
        puts format(
          '[youfm] spotify playlist page fetched: playlist_id=%<playlist_id>s offset=%<offset>s limit=%<limit>s elapsed=%<elapsed>.2fs',
          playlist_id: playlist_id,
          offset: offset,
          limit: limit,
          elapsed: elapsed
        )
        tracks = Array(body['items']).filter_map do |item|
          track_payload = item['item'] || item['track']
          next unless track_payload.is_a?(Hash)
          next if track_payload['type'].to_s == 'episode'

          build_track(track_payload)
        end
        serialized_tracks = tracks.map { |track| serialize_track(track) }
        has_more = !body['next'].to_s.empty?
        playlist_cache&.save(
          playlist_id: playlist_id,
          snapshot_id: snapshot_id,
          offset: offset,
          limit: limit,
          tracks: serialized_tracks,
          has_more: has_more
        )

        {
          tracks: tracks,
          has_more: has_more
        }
      end

      def cached_playlist_tracks_page(playlist_id, limit: 100, offset: 0, snapshot_id: nil)
        cached_page = playlist_cache&.fetch(playlist_id:, snapshot_id:, offset:, limit:)
        return nil unless cached_page

        hydrate_playlist_page(cached_page)
      end

      def cached_playlist_tracks(playlist_id, limit: 100, snapshot_id: nil)
        return nil if snapshot_id.to_s.empty?

        tracks = []
        offset = 0

        loop do
          page = cached_playlist_tracks_page(playlist_id, limit:, offset:, snapshot_id:)
          return nil unless page

          tracks.concat(page[:tracks])
          break unless page[:has_more]

          offset += limit
        end

        tracks
      end

      def play_track(track_uri)
        put('/me/player/play', { uris: [track_uri] })
      end

      def play_playlist(playlist_uri, device_id: nil)
        params = device_id ? { device_id: device_id } : {}
        put('/me/player/play', { context_uri: playlist_uri }, params:)
      end

      def add_to_queue(track_uri)
        post('/me/player/add-to-queue', uri: track_uri)
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

      def skip_to_next
        post('/me/player/next')
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

      attr_reader :access_token, :base_url, :token_store, :authenticator, :playlist_cache

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
          tracks_total: playlist_items_total(item),
          snapshot_id: item['snapshot_id']
        )
      end

      def hydrate_playlist_page(page)
        {
          tracks: Array(page[:tracks]).map { |track_payload| build_track(track_payload) },
          has_more: page[:has_more] == true
        }
      end

      def serialize_track(track)
        {
          'id' => track.id,
          'name' => track.title,
          'artists' => track.artists.map { |artist| { 'name' => artist } },
          'album' => { 'name' => track.album },
          'uri' => track.uri,
          'duration_ms' => track.duration_ms
        }
      end

      def get(path, params = {})
        body, = get_with_code(path, params)
        body
      end

      def get_with_code(path, params = {})
        request(Net::HTTP::Get.new(build_uri(path, params)))
      end

      def put(path, payload, params: {})
        body, = request(
          Net::HTTP::Put.new(build_uri(path, params)).tap do |request|
            request.body = JSON.dump(payload)
          end
        )
        body
      end

      def post(path, params = {})
        body, = request(Net::HTTP::Post.new(build_uri(path, params)))
        body
      end

      def build_uri(path, params = {})
        uri = URI.join(base_url.end_with?('/') ? base_url : "#{base_url}/", path.sub(%r{\A/}, ''))
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def request(request)
        enforce_rate_limit!
        ensure_token!
        response = perform_request(request, bearer_token)
        if response.code.to_i == 401 && refreshable?
          refreshed_token = refresh_bearer_token!
          response = perform_request(request, refreshed_token)
        end

        handle_response(response, request)
      end

      def handle_response(response, request)
        code = response.code.to_i
        body = response.body.to_s
        raise AuthenticationError, 'Spotify access token is missing or expired' if code == 401
        raise rate_limited_error_for(response, body) if code == 429
        raise playback_error_for(code, body, request) if playback_error_for(code, body, request)
        raise Error, extract_error_message(body) if code >= 400 && code != 204

        return [{}, 204] if code == 204 || body.strip.empty?

        [JSON.parse(body), code]
      rescue JSON::ParserError
        [{}, code]
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

        puts "[youfm] spotify request: #{request.method} #{request.uri}"
        Net::HTTP.start(
          request.uri.host,
          request.uri.port,
          use_ssl: request.uri.scheme == 'https',
          open_timeout: 5,
          read_timeout: 10
        ) do |http|
          http.request(request)
        end
      rescue Net::OpenTimeout, Net::ReadTimeout
        raise TimeoutError, 'Spotify request timed out'
      end

      def playback_error_for(code, body, request)
        return nil unless playback_request?(request)

        message = extract_error_message(body)
        return PlaybackUnavailableError.new(message) if code == 403
        return DeviceUnavailableError.new(message) if code == 404

        nil
      end

      def playback_request?(request)
        request.uri.path.include?('/me/player')
      end

      def rate_limited_error_for(response, body)
        retry_after_seconds = Integer(response['Retry-After'], exception: false)
        @rate_limited_until = retry_after_seconds && retry_after_seconds.positive? ? Time.now + retry_after_seconds : nil
        message = extract_error_message(body)
        message = 'Too many requests' if message.to_s.strip.empty?
        RateLimitedError.new(message, retry_after_seconds: retry_after_seconds)
      end

      def search_tracks_body(query, limit:)
        get('/search', q: query, type: 'track', limit: limit)
      rescue Error => e
        raise unless e.message == 'Invalid limit' && !limit.nil?

        get('/search', q: query, type: 'track')
      end

      def enforce_rate_limit!
        return unless @rate_limited_until && Time.now < @rate_limited_until

        remaining_seconds = (@rate_limited_until - Time.now).ceil
        raise RateLimitedError.new(
          "Spotify rate limit active, retry in #{remaining_seconds}s",
          retry_after_seconds: remaining_seconds
        )
      end

      def extract_error_message(body)
        parsed = JSON.parse(body)
        parsed.dig('error', 'message').to_s.strip.then { |message| message.empty? ? body : message }
      rescue JSON::ParserError
        body
      end

      def normalize_search_limit(limit)
        parsed = Integer(limit, exception: false)
        return 20 if parsed.nil? || parsed <= 0

        [parsed, 50].min
      end

      def playlist_items_total(item)
        item.dig('items', 'total') || item.dig('tracks', 'total') || 0
      end
    end
  end
end
