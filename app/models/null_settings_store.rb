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
    end
  end
end
