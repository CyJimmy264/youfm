# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationGenerator
      DEFAULT_SIMILAR_ARTIST_POOL_LIMIT = RecommendationStrategies::ArtistSimilarTopTracks::
        DEFAULT_SIMILAR_ARTIST_POOL_LIMIT
      DEFAULT_ENABLED_SEED_SOURCES = %i[current_playlist].freeze
      DEFAULT_ENABLED_GENERATORS = %i[artist_similar_top_tracks].freeze
      DEFAULT_GENERATOR_WEIGHT = 1
      DEFAULT_EXCLUDE_EXPLICIT = true
      SEED_SOURCE_NAMES = %i[current_playlist recent_tracks loved_tracks].freeze
      GENERATOR_NAMES = %i[raw_seed artist_similar_top_tracks track_similar].freeze
      Recommendation = Struct.new(:track, :seed_track, :seed_label, keyword_init: true)

      def initialize(lastfm_client:, spotify_client:, similar_artist_pool_limit: DEFAULT_SIMILAR_ARTIST_POOL_LIMIT,
                     enabled_seed_source_names: DEFAULT_ENABLED_SEED_SOURCES,
                     enabled_generator_names: DEFAULT_ENABLED_GENERATORS,
                     generator_weights: {},
                     enabled_strategy_names: nil,
                     exclude_explicit: DEFAULT_EXCLUDE_EXPLICIT, random: Random.new)
        @matcher = RecommendationTrackMatcher.new(spotify_client: spotify_client, exclude_explicit: exclude_explicit)
        @seed_sources = {
          current_playlist: RecommendationSeedSources::CurrentPlaylist.new,
          recent_tracks: RecommendationSeedSources::RecentTracks.new(lastfm_client: lastfm_client, random: random),
          loved_tracks: RecommendationSeedSources::LovedTracks.new(lastfm_client: lastfm_client, random: random)
        }
        artist_similar_top_tracks = RecommendationStrategies::ArtistSimilarTopTracks.new(
          lastfm_client: lastfm_client,
          matcher: matcher,
          similar_artist_pool_limit: similar_artist_pool_limit,
          random: random
        )
        @generators = {
          raw_seed: RecommendationStrategies::RawSeed.new(matcher: matcher),
          artist_similar_top_tracks: artist_similar_top_tracks,
          track_similar: RecommendationStrategies::TrackSimilar.new(
            lastfm_client: lastfm_client,
            matcher: matcher,
            fallback_strategy: artist_similar_top_tracks
          )
        }
        @random = random
        if enabled_strategy_names
          self.enabled_strategy_names = enabled_strategy_names
        else
          self.enabled_seed_source_names = enabled_seed_source_names
          self.enabled_generator_names = enabled_generator_names
        end
        self.generator_weights = generator_weights
      end

      attr_reader :enabled_seed_source_names, :enabled_generator_names, :generator_weights

      def enabled_strategy_names
        names = enabled_generator_names - [:raw_seed]
        if enabled_seed_source_names.include?(:recent_tracks) && enabled_generator_names.include?(:raw_seed)
          names << :recent_tracks
        end
        if enabled_seed_source_names.include?(:loved_tracks) && enabled_generator_names.include?(:raw_seed)
          names << :loved_tracks
        end
        names
      end

      def exclude_explicit?
        matcher.exclude_explicit
      end

      def exclude_explicit=(value)
        matcher.exclude_explicit = value == true
      end

      def similar_artist_pool_limit
        generators.fetch(:artist_similar_top_tracks).similar_artist_pool_limit
      end

      def similar_artist_pool_limit=(value)
        generators.fetch(:artist_similar_top_tracks).similar_artist_pool_limit = value
      end

      def enabled_seed_source_names=(names)
        @enabled_seed_source_names = Array(names).filter_map do |name|
          normalized_name = name.to_s.strip.to_sym
          normalized_name if SEED_SOURCE_NAMES.include?(normalized_name)
        end.uniq
      end

      def enabled_generator_names=(names)
        @enabled_generator_names = Array(names).filter_map do |name|
          normalized_name = name.to_s.strip.to_sym
          normalized_name if GENERATOR_NAMES.include?(normalized_name)
        end.uniq
      end

      def enabled_strategy_names=(names)
        normalized_names = Array(names).map(&:to_sym)
        sources = []
        sources << :current_playlist if normalized_names.intersect?(GENERATOR_NAMES - [:raw_seed])
        sources << :recent_tracks if normalized_names.include?(:recent_tracks)
        sources << :loved_tracks if normalized_names.include?(:loved_tracks)
        generators = normalized_names & (GENERATOR_NAMES - [:raw_seed])
        generators << :raw_seed if normalized_names.intersect?(%i[recent_tracks loved_tracks])
        sources = DEFAULT_ENABLED_SEED_SOURCES if sources.empty? && generators.any? && generators != [:raw_seed]
        generators = DEFAULT_ENABLED_GENERATORS if generators.empty? && normalized_names.any?
        self.enabled_seed_source_names = sources
        self.enabled_generator_names = generators
      end

      def generator_weights=(weights)
        @generator_weights = GENERATOR_NAMES.each_with_object({}) do |name, normalized|
          raw_weight = weights.to_h.fetch(name, weights.to_h.fetch(name.to_s, DEFAULT_GENERATOR_WEIGHT))
          parsed = Integer(raw_weight, exception: false)
          normalized[name] = parsed&.positive? ? parsed : DEFAULT_GENERATOR_WEIGHT
        end
      end

      def supports_seedless_generation?
        enabled_seed_source_names.any? { |name| name != :current_playlist }
      end

      def generate_from_playlist(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        generate_with_seed(seed_tracks, excluded_track_ids:, playlist_name:)&.track
      end

      def generate_with_seed(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        return nil if enabled_seed_source_names.empty? || enabled_generator_names.empty?

        blocked_track_ids = excluded_track_ids.map(&:to_s).reject(&:empty?).to_set
        source_name = pick_seed_source_name(seed_tracks)
        return nil unless source_name

        candidates = seed_sources.fetch(source_name).fetch(
          seed_tracks:,
          blocked_track_ids: blocked_track_ids,
          playlist_name: playlist_name,
          random: random
        )
        generator_name = pick_generator_name
        return nil unless generator_name

        candidates.each do |candidate|
          recommendation = generators.fetch(generator_name).generate(
            seed_track: candidate.track,
            blocked_track_ids: blocked_track_ids,
            playlist_name: playlist_name
          )
          next unless recommendation

          recommendation.seed_label ||= candidate.seed_label
          return recommendation
        end

        nil
      end

      private

      attr_reader :matcher, :seed_sources, :generators, :random

      def pick_seed_source_name(seed_tracks)
        available_names = enabled_seed_source_names.select do |name|
          name != :current_playlist || seed_tracks.any?
        end
        return nil if available_names.empty?
        return available_names.first if available_names.length == 1

        available_names.fetch(random.rand(available_names.length))
      end

      def pick_generator_name
        weighted_names = enabled_generator_names.flat_map do |name|
          [name] * generator_weights.fetch(name, DEFAULT_GENERATOR_WEIGHT)
        end
        return nil if weighted_names.empty?
        return weighted_names.first if weighted_names.length == 1

        weighted_names.fetch(random.rand(weighted_names.length))
      end
    end
  end
end
