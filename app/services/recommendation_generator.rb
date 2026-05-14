# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationGenerator
      DEFAULT_SIMILAR_ARTIST_POOL_LIMIT = RecommendationStrategies::ArtistSimilarTopTracks::
        DEFAULT_SIMILAR_ARTIST_POOL_LIMIT
      DEFAULT_ENABLED_STRATEGIES = %i[artist_similar_top_tracks].freeze
      DEFAULT_EXCLUDE_EXPLICIT = true
      STRATEGY_NAMES = %i[artist_similar_top_tracks track_similar recent_tracks].freeze
      SEEDLESS_STRATEGY_NAMES = %i[recent_tracks].freeze
      Recommendation = Struct.new(:track, :seed_track, :seed_label, keyword_init: true)

      def initialize(lastfm_client:, spotify_client:, similar_artist_pool_limit: DEFAULT_SIMILAR_ARTIST_POOL_LIMIT,
                     enabled_strategy_names: DEFAULT_ENABLED_STRATEGIES, exclude_explicit: DEFAULT_EXCLUDE_EXPLICIT,
                     random: Random.new)
        @matcher = RecommendationTrackMatcher.new(spotify_client: spotify_client, exclude_explicit: exclude_explicit)
        @strategies = {
          artist_similar_top_tracks: RecommendationStrategies::ArtistSimilarTopTracks.new(
            lastfm_client: lastfm_client,
            matcher: matcher,
            similar_artist_pool_limit: similar_artist_pool_limit,
            random: random
          ),
          track_similar: RecommendationStrategies::TrackSimilar.new(lastfm_client: lastfm_client, matcher: matcher),
          recent_tracks: RecommendationStrategies::RecentTracks.new(
            lastfm_client: lastfm_client,
            matcher: matcher,
            random: random
          )
        }
        self.enabled_strategy_names = enabled_strategy_names
      end

      attr_reader :enabled_strategy_names

      def exclude_explicit?
        matcher.exclude_explicit
      end

      def exclude_explicit=(value)
        matcher.exclude_explicit = value == true
      end

      def similar_artist_pool_limit
        strategies.fetch(:artist_similar_top_tracks).similar_artist_pool_limit
      end

      def similar_artist_pool_limit=(value)
        strategies.fetch(:artist_similar_top_tracks).similar_artist_pool_limit = value
      end

      def enabled_strategy_names=(names)
        @enabled_strategy_names = Array(names).filter_map do |name|
          normalized_name = name.to_s.strip.to_sym
          normalized_name if STRATEGY_NAMES.include?(normalized_name)
        end.uniq
      end

      def supports_seedless_generation?
        enabled_strategy_names.intersect?(SEEDLESS_STRATEGY_NAMES)
      end

      def generate_from_playlist(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        generate_with_seed(seed_tracks, excluded_track_ids: excluded_track_ids, playlist_name: playlist_name)&.track
      end

      def generate_with_seed(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        return nil if enabled_strategy_names.empty?

        blocked_track_ids = excluded_track_ids.map(&:to_s).reject(&:empty?).to_set

        return recommendation_without_seed(blocked_track_ids, playlist_name) if seed_tracks.empty?

        seed_tracks.shuffle.each do |seed_track|
          recommendation = recommendation_for_seed_track(seed_track, blocked_track_ids, playlist_name)
          return recommendation if recommendation
        end

        nil
      end

      private

      attr_reader :matcher, :strategies

      def recommendation_without_seed(blocked_track_ids, playlist_name)
        return nil unless supports_seedless_generation?

        (enabled_strategy_names & SEEDLESS_STRATEGY_NAMES).shuffle.each do |strategy_name|
          recommendation = strategies.fetch(strategy_name).generate(
            seed_track: nil,
            blocked_track_ids: blocked_track_ids,
            playlist_name: playlist_name
          )
          return recommendation if recommendation
        end

        nil
      end

      def recommendation_for_seed_track(seed_track, blocked_track_ids, playlist_name)
        enabled_strategy_names.shuffle.each do |strategy_name|
          recommendation = strategies.fetch(strategy_name).generate(
            seed_track: seed_track,
            blocked_track_ids: blocked_track_ids,
            playlist_name: playlist_name
          )
          return recommendation if recommendation
        end

        nil
      end
    end
  end
end
