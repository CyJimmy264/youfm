# frozen_string_literal: true

module YouFM
  module Models
    class NullSettingsStore
      def read_theme_name = nil
      def write_theme_name(_theme_name) = nil
      def read_similar_artist_pool_limit = nil
      def write_similar_artist_pool_limit(_limit) = nil
    end
  end
end
