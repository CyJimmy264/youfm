# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationGenerator
      DEFAULT_SIMILAR_ARTIST_POOL_LIMIT = 200
      SIMILAR_ARTIST_WINDOW_SIZE = 10
      TOP_TRACK_WINDOW_SIZE = 7
      TOP_TRACK_ATTEMPTS_PER_ARTIST = 3
      Recommendation = Struct.new(:track, :seed_track)

      def initialize(lastfm_client:, spotify_client:, similar_artist_pool_limit: DEFAULT_SIMILAR_ARTIST_POOL_LIMIT)
        @lastfm_client = lastfm_client
        @spotify_client = spotify_client
        self.similar_artist_pool_limit = similar_artist_pool_limit
      end

      attr_reader :similar_artist_pool_limit

      def similar_artist_pool_limit=(value)
        @similar_artist_pool_limit = normalize_pool_limit(value)
      end

      def generate_from_playlist(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        generate_with_seed(seed_tracks, excluded_track_ids: excluded_track_ids, playlist_name: playlist_name)&.track
      end

      def generate_with_seed(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        return nil if seed_tracks.empty?

        blocked_track_ids = excluded_track_ids.map(&:to_s).reject(&:empty?).to_set

        seed_tracks.shuffle.each do |seed_track|
          artist_name = seed_track.artists.first
          next unless artist_name

          similar_artists = @lastfm_client.get_similar_artists(artist_name, limit: similar_artist_pool_limit)
          next if similar_artists.empty?

          similar_artists_window(similar_artists).shuffle.each do |similar_artist|
            top_tracks = @lastfm_client.get_top_tracks(similar_artist.name, period: '12month', limit: 20)
            next if top_tracks.empty?

            top_tracks.shuffle.take([TOP_TRACK_WINDOW_SIZE, TOP_TRACK_ATTEMPTS_PER_ARTIST].min).each do |top_track|
              query = "#{top_track.name} artist:#{similar_artist.name}"
              spotify_tracks = @spotify_client.search_tracks(query, limit: 10)
              candidate = spotify_tracks.find do |track|
                next false if blocked_track_ids.include?(track.id.to_s)

                spotify_track_matches?(track, generated_artist_name: similar_artist.name,
                                              generated_title: top_track.name)
              end
              next unless candidate

              Services::Logger.info(
                "[youfm] recommendation generated: playlist=#{playlist_name || 'unknown'} " \
                "seed=#{seed_track.display_label.inspect} result=#{candidate.display_label.inspect}"
              )
              return Recommendation.new(track: candidate, seed_track: seed_track)
            end
          end
        end

        nil
      rescue LastfmClient::Error => e
        Services::Logger.warn("[youfm] Last.fm API error during recommendation: #{e.message}")
        nil
      rescue SpotifyClient::Error => e
        Services::Logger.warn("[youfm] Spotify API error during recommendation: #{e.message}")
        nil
      end

      private

      def similar_artists_window(similar_artists)
        window_size = [SIMILAR_ARTIST_WINDOW_SIZE, similar_artists.length].min
        offset = rand(similar_artists.length).floor
        window = similar_artists.rotate(offset).first(window_size)
        Services::Logger.info(
          "[youfm] recommendation similar artists: total=#{similar_artists.length} " \
          "pool_limit=#{similar_artist_pool_limit} offset=#{offset} window=#{window.map(&:name).join(' | ')}"
        )
        window
      end

      def spotify_track_matches?(track, generated_artist_name:, generated_title:)
        spotify_artist = normalize_text(track.artists.first)
        spotify_title = normalize_text(track.title)
        artist_name = normalize_text(generated_artist_name)
        title = normalize_text(generated_title)

        (spotify_artist.include?(artist_name) || artist_name.include?(spotify_artist)) &&
          (spotify_title.include?(title) || title.include?(spotify_title))
      end

      def normalize_text(value)
        value.to_s.downcase.gsub(/(remastered(\s\d+)*|the)/, ' ').gsub(/[^a-z0-9]+/, ' ').strip
      end

      def normalize_pool_limit(value)
        parsed = Integer(value, exception: false)
        return DEFAULT_SIMILAR_ARTIST_POOL_LIMIT if parsed.nil? || parsed <= 0

        parsed
      end
    end
  end
end
