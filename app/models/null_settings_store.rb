# frozen_string_literal: true

module YouFM
  module Models
    class NullSettingsStore
      def read_theme_name = nil
      def write_theme_name(_theme_name) = nil
    end
  end
end
