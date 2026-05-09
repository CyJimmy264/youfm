# frozen_string_literal: true

module YouFM
  module Models
    class Track
      extend Props

      props :id, :title, :artists, :album, :uri, :duration_ms

      def artist_line
        artists.join(', ')
      end

      def display_label
        "#{title} - #{artist_line}"
      end
    end
  end
end
