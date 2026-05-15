# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class ArtistSimilarTopTracks
        DEFAULT_SIMILAR_ARTIST_POOL_LIMIT = 200
        SIMILAR_ARTIST_WINDOW_SIZE = 10
        TOP_TRACK_WINDOW_SIZE = 7
        TOP_TRACK_ATTEMPTS_PER_ARTIST = 3

        def initialize(lastfm_client:, matcher:, similar_artist_pool_limit:, random:, fallback_strategy: nil)
          @lastfm_client = lastfm_client
          @matcher = matcher
          @random = random
          @fallback_strategy = fallback_strategy
          self.similar_artist_pool_limit = similar_artist_pool_limit
        end

        attr_reader :similar_artist_pool_limit

        def similar_artist_pool_limit=(value)
          @similar_artist_pool_limit = normalize_pool_limit(value)
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          artist_name = seed_track.artists.first
          return nil unless artist_name

          similar_artists = lastfm_client.get_similar_artists(artist_name, limit: similar_artist_pool_limit)
          if similar_artists.empty?
            return fallback(seed_track, blocked_track_ids, playlist_name, reason: 'no_lastfm_similar_artists')
          end

          similar_artists_window(similar_artists).shuffle.each do |similar_artist|
            recommendation = recommendation_for_similar_artist(
              similar_artist, blocked_track_ids, seed_track, playlist_name
            )
            return recommendation if recommendation
          end

          fallback(seed_track, blocked_track_ids, playlist_name, reason: 'no_spotify_match_from_similar_artists')
        end

        private

        attr_reader :lastfm_client, :matcher, :random, :fallback_strategy

        def recommendation_for_similar_artist(similar_artist, blocked_track_ids, seed_track, playlist_name)
          top_tracks = lastfm_client.get_top_tracks(similar_artist.name, period: '12month', limit: 20)
          return nil if top_tracks.empty?

          top_tracks.shuffle.take([TOP_TRACK_WINDOW_SIZE, TOP_TRACK_ATTEMPTS_PER_ARTIST].min).each do |top_track|
            candidate = matcher.spotify_track_candidate_for(
              artist_name: similar_artist.name,
              track_name: top_track.name,
              blocked_track_ids: blocked_track_ids
            )
            next unless candidate

            log_recommendation(seed_track, candidate, playlist_name)
            return RecommendationGenerator::Recommendation.new(track: candidate, seed_track: seed_track)
          end

          nil
        end

        def similar_artists_window(similar_artists)
          window_size = [SIMILAR_ARTIST_WINDOW_SIZE, similar_artists.length].min
          offset = random.rand(similar_artists.length).floor
          window = similar_artists.rotate(offset).first(window_size)
          Services::Logger.info(
            "[youfm] recommendation similar artists: total=#{similar_artists.length} " \
            "pool_limit=#{similar_artist_pool_limit} offset=#{offset} window=#{window.map(&:name).join(' | ')}"
          )
          window
        end

        def log_recommendation(seed_track, candidate, playlist_name)
          Services::Logger.info(
            '[youfm] recommendation generated: strategy=artist_similar_top_tracks ' \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track.display_label.inspect} " \
            "result=#{candidate.display_label.inspect} id=#{candidate.id.inspect} uri=#{candidate.uri.to_s.inspect}"
          )
        end

        def fallback(seed_track, blocked_track_ids, playlist_name, reason:)
          Services::Logger.info(
            '[youfm] recommendation fallback: strategy=artist_similar_top_tracks ' \
            "reason=#{reason} seed=#{seed_track.display_label.inspect}"
          )
          fallback_strategy&.generate(
            seed_track: seed_track,
            blocked_track_ids: blocked_track_ids,
            playlist_name: playlist_name
          )
        end

        def normalize_pool_limit(value)
          parsed = Integer(value, exception: false)
          return DEFAULT_SIMILAR_ARTIST_POOL_LIMIT if parsed.nil? || parsed <= 0

          parsed
        end
      end
    end
  end
end
