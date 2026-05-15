# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class SameArtist
        TOP_TRACK_LIMIT = 20
        TOP_TRACK_WINDOW_SIZE = 10

        def initialize(lastfm_client:, matcher:)
          @lastfm_client = lastfm_client
          @matcher = matcher
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          artist_name = seed_track.artists.first
          return nil if artist_name.to_s.empty?

          top_tracks = lastfm_client.get_top_tracks(artist_name, period: '12month', limit: TOP_TRACK_LIMIT)
          return nil if top_tracks.empty?

          top_tracks.shuffle.take(TOP_TRACK_WINDOW_SIZE).each do |top_track|
            candidate = matcher.spotify_track_candidate_for(
              artist_name: artist_name,
              track_name: top_track.name,
              blocked_track_ids: blocked_track_ids
            )
            next unless candidate

            log_recommendation(seed_track, candidate, playlist_name)
            return RecommendationGenerator::Recommendation.new(track: candidate, seed_track: seed_track)
          end

          nil
        end

        private

        attr_reader :lastfm_client, :matcher

        def log_recommendation(seed_track, candidate, playlist_name)
          Services::Logger.info(
            '[youfm] recommendation generated: strategy=same_artist ' \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track.display_label.inspect} " \
            "result=#{candidate.display_label.inspect} id=#{candidate.id.inspect} uri=#{candidate.uri.to_s.inspect}"
          )
        end
      end
    end
  end
end
