# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class TrackSimilar
        SIMILAR_TRACK_LIMIT = 20
        SIMILAR_TRACK_WINDOW_SIZE = 10

        def initialize(lastfm_client:, matcher:, fallback_strategy: nil)
          @lastfm_client = lastfm_client
          @matcher = matcher
          @fallback_strategy = fallback_strategy
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          seed_artist = seed_track.artists.first
          return nil unless seed_artist

          similar_tracks = lastfm_client.get_similar_tracks(
            seed_artist,
            seed_track.title,
            limit: SIMILAR_TRACK_LIMIT
          )
          return fallback(seed_track, blocked_track_ids, playlist_name) if similar_tracks.empty?

          similar_tracks.sample(SIMILAR_TRACK_WINDOW_SIZE).each do |similar_track|
            candidate = matcher.spotify_track_candidate_for(
              artist_name: similar_track.artist_name,
              track_name: similar_track.name,
              blocked_track_ids: blocked_track_ids
            )
            next unless candidate

            log_recommendation(seed_track, candidate, playlist_name)
            return RecommendationGenerator::Recommendation.new(track: candidate, seed_track: seed_track)
          end

          nil
        end

        private

        attr_reader :lastfm_client, :matcher, :fallback_strategy

        def fallback(seed_track, blocked_track_ids, playlist_name)
          Services::Logger.info(
            '[youfm] recommendation fallback: strategy=track_similar ' \
            "reason=no_lastfm_similar_tracks seed=#{seed_track.display_label.inspect}"
          )
          fallback_strategy&.generate(
            seed_track: seed_track,
            blocked_track_ids: blocked_track_ids,
            playlist_name: playlist_name
          )
        end

        def log_recommendation(seed_track, candidate, playlist_name)
          Services::Logger.info(
            '[youfm] recommendation generated: strategy=track_similar ' \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track.display_label.inspect} " \
            "result=#{candidate.display_label.inspect} id=#{candidate.id.inspect} uri=#{candidate.uri.to_s.inspect}"
          )
        end
      end
    end
  end
end
