# frozen_string_literal: true

module YouFM
  module Models
    class NullSettingsStore
      def read_theme_name = nil
      def write_theme_name(_theme_name) = nil
      def read_similar_artist_pool_limit = nil
      def write_similar_artist_pool_limit(_limit) = nil
      def read_minimum_recommended_queue_size = nil
      def write_minimum_recommended_queue_size(_size) = nil
      def read_maximum_recommended_queue_size = nil
      def write_maximum_recommended_queue_size(_size) = nil
      def read_enabled_recommendation_strategy_names = nil
      def write_enabled_recommendation_strategy_names(_names) = nil
      def read_enabled_seed_source_names = nil
      def write_enabled_seed_source_names(_names) = nil
      def read_seed_source_weights = nil
      def write_seed_source_weights(_weights) = nil
      def read_enabled_generator_names = nil
      def write_enabled_generator_names(_names) = nil
      def read_generator_weights = nil
      def write_generator_weights(_weights) = nil
      def read_exclude_explicit_recommendations = nil
      def write_exclude_explicit_recommendations(_value) = nil
      def read_replay_seed_before_recommendation = nil
      def write_replay_seed_before_recommendation(_value) = nil
      def read_seed_replay_interval = nil
      def write_seed_replay_interval(_value) = nil
      def read_recommendation_title_blacklist = nil
      def write_recommendation_title_blacklist(_lines) = nil
    end
  end
end
