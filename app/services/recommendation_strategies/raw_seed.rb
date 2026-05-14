# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class RawSeed
        def initialize(matcher:)
          @matcher = matcher
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          return nil unless seed_track

          candidate = raw_seed_candidate(seed_track, blocked_track_ids)
          return nil unless candidate

          Services::Logger.info(
            '[youfm] recommendation generated: strategy=raw_seed ' \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track.display_label.inspect} " \
            "result=#{candidate.display_label.inspect}"
          )
          RecommendationGenerator::Recommendation.new(track: candidate, seed_track: nil)
        end

        private

        attr_reader :matcher

        def raw_seed_candidate(seed_track, blocked_track_ids)
          return seed_track if reusable_seed_track?(seed_track, blocked_track_ids)

          matcher.spotify_track_candidate_for(
            artist_name: seed_track.artists.first,
            track_name: seed_track.title,
            blocked_track_ids: blocked_track_ids
          )
        end

        def reusable_seed_track?(seed_track, blocked_track_ids)
          seed_track.uri &&
            !blocked_track_ids.include?(seed_track.id.to_s) &&
            !(matcher.exclude_explicit && seed_track.explicit)
        end
      end
    end
  end
end
