# frozen_string_literal: true

require 'httpx'
require 'json'
require 'digest/md5'
require 'time'
require 'cgi'
require 'uri'

module YouFM
  module Services
    class LastfmClient
      class Error < StandardError; end
      SIMILAR_ARTISTS_CACHE_TTL = 7 * 24 * 60 * 60
      TOP_TRACKS_CACHE_TTL = 24 * 60 * 60
      SIMILAR_ARTISTS_API_LIMIT = 100
      LASTFM_WEB_BASE_URL = 'https://www.last.fm'
      HTTP_OPEN_TIMEOUT = 5
      HTTP_READ_TIMEOUT = 10
      WEB_USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ' \
                       '(KHTML, like Gecko) Chrome/123.0 Safari/537.36'

      def initialize(api_key:, secret:, session_key: nil, session_key_provider: nil, username_provider: nil,
                     base_url: 'http://ws.audioscrobbler.com/2.0/', similar_artists_cache: nil,
                     top_tracks_cache: nil, api_http_client: nil, web_http_client: nil)
        @api_key = api_key
        @secret = secret
        @session_key = session_key
        @session_key_provider = session_key_provider
        @username_provider = username_provider
        @base_url = base_url
        @similar_artists_cache = similar_artists_cache
        @top_tracks_cache = top_tracks_cache
        @api_http_client = api_http_client ||
                           PersistentHttpClient.new(open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT)
        @web_http_client = web_http_client ||
                           PersistentHttpClient.new(open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT)
      end

      SimilarArtist = Struct.new(:name, :match)
      TopTrack = Struct.new(:name, :playcount, :listeners)
      SimilarTrack = Struct.new(:name, :artist_name, :match)
      RecentTrack = Struct.new(:name, :artist_name, :album_name, :played_at)
      LovedTrack = Struct.new(:name, :artist_name, :album_name, :loved_at)
      UserTracksPage = Struct.new(:tracks, :page, :total_pages)

      def auth_get_token
        get({ method: 'auth.getToken' })
      end

      def auth_get_session(token)
        get({ method: 'auth.getSession', token: token }, signed: true)
      end

      def get_similar_artists(artist_name, limit: nil)
        desired_limit = normalize_limit(limit)
        cached_artists_payload = similar_artists_cache&.fetch(artist_name, ttl: SIMILAR_ARTISTS_CACHE_TTL)
        if cached_artists_payload
          if desired_limit.nil? || cached_artists_payload.length >= desired_limit
            return build_similar_artists(truncate_similar_artists_payload(cached_artists_payload,
                                                                          desired_limit))
          end

          web_artists_payload = fetch_similar_artists_from_web(artist_name, limit: desired_limit)
          artists_payload = merge_similar_artists_payloads(cached_artists_payload, web_artists_payload)
          if artists_payload.length > cached_artists_payload.length
            similar_artists_cache&.save(artist_name,
                                        artists_payload)
          end
          return build_similar_artists(truncate_similar_artists_payload(artists_payload, desired_limit))
        end

        artists_payload = fetch_similar_artists_via_api(artist_name)
        if desired_limit && desired_limit > artists_payload.length
          web_artists_payload = fetch_similar_artists_from_web(artist_name, limit: desired_limit)
          artists_payload = merge_similar_artists_payloads(artists_payload, web_artists_payload)
        end

        similar_artists_cache&.save(artist_name, artists_payload)
        build_similar_artists(truncate_similar_artists_payload(artists_payload, desired_limit))
      end

      def get_top_tracks(artist_name, limit: 10, period: '12month')
        cached_tracks_payload = top_tracks_cache&.fetch(
          artist_name,
          period: period,
          limit: limit,
          ttl: TOP_TRACKS_CACHE_TTL
        )
        return build_top_tracks(cached_tracks_payload) if cached_tracks_payload

        body = get({ method: 'artist.getTopTracks', artist: artist_name, limit: limit, period: period }, signed: true)
        tracks_payload = Array(body.dig('toptracks', 'track'))
        top_tracks_cache&.save(artist_name, period: period, limit: limit, tracks: tracks_payload)
        build_top_tracks(tracks_payload)
      end

      def get_similar_tracks(artist_name, track_name, limit: 20)
        body = get({ method: 'track.getSimilar', artist: artist_name, track: track_name, limit: limit }, signed: true)
        build_similar_tracks(Array(body.dig('similartracks', 'track')))
      end

      def get_recent_tracks(page: 1, limit: 10, user: nil)
        user_tracks_page(
          method_name: 'user.getRecentTracks',
          page: page,
          limit: limit,
          user: user,
          payload_key: 'recenttracks',
          tracks_key: 'track',
          build_tracks: method(:build_recent_tracks)
        )
      end

      def get_loved_tracks(page: 1, limit: 10, user: nil)
        user_tracks_page(
          method_name: 'user.getLovedTracks',
          page: page,
          limit: limit,
          user: user,
          payload_key: 'lovedtracks',
          tracks_key: 'track',
          build_tracks: method(:build_loved_tracks)
        )
      end

      private

      attr_reader :api_key, :secret, :base_url, :similar_artists_cache, :top_tracks_cache

      def fetch_similar_artists_via_api(artist_name)
        body = get({ method: 'artist.getSimilar', artist: artist_name }, signed: true)
        Array(body.dig('similarartists', 'artist')).first(SIMILAR_ARTISTS_API_LIMIT)
      end

      def build_similar_artists(artists)
        artists.map do |artist_data|
          SimilarArtist.new(
            name: artist_data['name'],
            match: artist_data['match'].to_f
          )
        end
      end

      def build_top_tracks(tracks)
        tracks.map do |track_data|
          TopTrack.new(
            name: track_data['name'],
            playcount: track_data['playcount'].to_i,
            listeners: track_data['listeners'].to_i
          )
        end
      end

      def build_similar_tracks(tracks)
        tracks.map do |track_data|
          SimilarTrack.new(
            name: track_data['name'],
            artist_name: track_data.dig('artist', 'name').to_s,
            match: track_data['match'].to_f
          )
        end
      end

      def build_recent_tracks(tracks)
        tracks.filter_map do |track_data|
          artist_name = track_data.dig('artist', '#text').to_s
          track_name = track_data['name'].to_s
          next if artist_name.empty? || track_name.empty?

          RecentTrack.new(
            name: track_name,
            artist_name: artist_name,
            album_name: track_data.dig('album', '#text').to_s,
            played_at: track_data.dig('date', 'uts').to_s
          )
        end
      end

      def build_loved_tracks(tracks)
        tracks.filter_map do |track_data|
          artist_name = track_data.dig('artist', 'name').to_s
          track_name = track_data['name'].to_s
          next if artist_name.empty? || track_name.empty?

          LovedTrack.new(
            name: track_name,
            artist_name: artist_name,
            album_name: track_data['album'].to_s,
            loved_at: track_data.dig('date', 'uts').to_s
          )
        end
      end

      def get(params = {}, signed: false)
        params[:api_key] = api_key
        params[:format] = 'json'
        active_session_key = current_session_key
        params[:sk] = active_session_key if signed && active_session_key
        params[:api_sig] = sign(params) if signed

        uri = build_uri(params)
        response = perform_api_request(uri)
        handle_response(response)
      end

      def user_tracks_page(method_name:, page:, limit:, user:, payload_key:, tracks_key:, build_tracks:)
        username = user.to_s.strip
        username = current_username if username.empty?
        raise Error, 'Last.fm username is unavailable' if username.empty?

        body = get(
          { method: method_name, user: username, page: page, limit: limit },
          signed: true
        )
        payload = body.fetch(payload_key, {})
        UserTracksPage.new(
          tracks: build_tracks.call(Array(payload[tracks_key])),
          page: payload.fetch('@attr', {}).fetch('page', page).to_i,
          total_pages: payload.fetch('@attr', {}).fetch('totalPages', 1).to_i
        )
      end

      def perform_api_request(uri)
        request = HttpRequest.get(uri)
        started_at = HttpRequestLogger.monotonic_time
        @api_http_client.request(request).tap do |response|
          log_http_request(uri, response.code, started_at)
        end
      rescue HTTPX::TimeoutError, HTTPX::ConnectionError
        log_http_request(uri, 'timeout', started_at)
        raise Error, 'Last.fm request timed out'
      end

      def sign(params)
        params_for_signing = params.reject { |k, _v| k.to_s == 'format' }
        param_string = params_for_signing.sort.map { |k, v| "#{k}#{v}" }.join
        Digest::MD5.hexdigest(param_string + secret)
      end

      def build_uri(params = {})
        uri = URI.parse(base_url)
        uri.query = URI.encode_www_form(params)
        uri
      end

      def handle_response(response)
        code = response.code.to_i
        body = response.body.to_s
        raise Error, "Last.fm API error: #{code} #{body}" if code >= 400

        JSON.parse(body)
      end

      def fetch_similar_artists_from_web(artist_name, limit:)
        return [] if limit <= SIMILAR_ARTISTS_API_LIMIT

        page = 1
        artists = []
        seen_names = Set.new

        while artists.length < limit && page <= max_web_pages(limit)
          html = get_web(similar_artists_web_uri(artist_name, page))
          break unless html

          page_artists = parse_similar_artists_from_html(html, artist_name:)
          break if page_artists.empty?

          page_artists.each do |artist_payload|
            normalized_name = normalize_name(artist_payload['name'])
            next if normalized_name.empty?
            next if seen_names.include?(normalized_name)

            seen_names << normalized_name
            artists << artist_payload
          end

          page += 1
        end

        artists.first(limit)
      end

      def parse_similar_artists_from_html(html, artist_name:)
        return [] if html.to_s.empty?
        return [] if blocked_web_response?(html)

        anchor_matches =
          html.scan(%r{<a[^>]*class="[^"]*link-block-target[^"]*"[^>]*href="/music/([^"/?#]+)"[^>]*>(.*?)</a>}im)
        anchor_matches = html.scan(%r{<a[^>]*href="/music/([^"/?#]+)"[^>]*>(.*?)</a>}im) if anchor_matches.empty?

        seen_names = Set.new
        anchor_matches.filter_map.with_index do |(encoded_name, inner_html), index|
          name = strip_html(inner_html)
          name = decode_artist_name(encoded_name) if name.empty?
          normalized_name = normalize_name(name)
          next if normalized_name.empty? || normalized_name == normalize_name(artist_name)
          next if seen_names.include?(normalized_name)

          seen_names << normalized_name
          { 'name' => name, 'match' => synthetic_web_match(index) }
        end
      end

      def synthetic_web_match(index)
        format('%.4f', [1.0 - (index * 0.001), 0.0].max)
      end

      def get_web(uri)
        response = perform_web_request(uri)
        code = response.code.to_i
        body = response.body.to_s
        return nil if code >= 400 || blocked_web_response?(body)

        body
      rescue StandardError
        nil
      end

      def perform_web_request(uri)
        request = HttpRequest.get(
          uri,
          headers: {
            'User-Agent' => WEB_USER_AGENT,
            'Accept' => 'text/html,application/xhtml+xml',
            'Accept-Language' => 'en-US,en;q=0.9'
          }
        )
        started_at = HttpRequestLogger.monotonic_time

        @web_http_client.request(request).tap do |response|
          log_http_request(uri, response.code, started_at)
        end
      end

      def log_http_request(uri, status, started_at)
        HttpRequestLogger.log(
          provider: :lastfm,
          method: 'GET',
          uri: uri,
          status: status,
          elapsed_ms: HttpRequestLogger.elapsed_ms_since(started_at)
        )
      end

      def similar_artists_web_uri(artist_name, page)
        escaped_artist = CGI.escape(artist_name.to_s).gsub('+', '%20')
        URI.parse("#{LASTFM_WEB_BASE_URL}/music/#{escaped_artist}/+similar?page=#{page}")
      end

      def blocked_web_response?(body)
        body.include?('Last.fm - Rate Limited') || body.include?('Your request was blocked')
      end

      def max_web_pages(limit)
        [(limit.to_f / 50).ceil + 2, 20].min
      end

      def merge_similar_artists_payloads(primary_payload, additional_payload)
        merged = []
        seen_names = Set.new

        [Array(primary_payload), Array(additional_payload)].each do |payload|
          payload.each do |artist_payload|
            normalized_name = normalize_name(artist_payload['name'])
            next if normalized_name.empty? || seen_names.include?(normalized_name)

            seen_names << normalized_name
            merged << artist_payload
          end
        end

        merged
      end

      def truncate_similar_artists_payload(payload, desired_limit)
        desired_limit ? payload.first(desired_limit) : payload
      end

      def normalize_limit(limit)
        parsed = Integer(limit, exception: false)
        return nil if parsed.nil? || parsed <= 0

        parsed
      end

      def strip_html(value)
        CGI.unescapeHTML(value.to_s.gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
      end

      def decode_artist_name(value)
        CGI.unescapeHTML(URI::DEFAULT_PARSER.unescape(value.to_s)).tr('+', ' ')
      end

      def normalize_name(value)
        value.to_s.downcase.gsub(/\s+/, ' ').strip
      end

      def current_session_key
        provided_session_key = @session_key_provider&.call.to_s.strip
        return provided_session_key unless provided_session_key.empty?

        @session_key.to_s.strip
      end

      def current_username
        @username_provider&.call.to_s.strip
      end
    end
  end
end
