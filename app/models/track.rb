# frozen_string_literal: true

module YouFM
  module Models
    class Track
      attr_reader :id, :title, :artists, :album, :uri, :duration_ms

      def initialize(id:, title:, artists:, album:, uri:, duration_ms:)
        @id = id
        @title = title
        @artists = artists
        @album = album
        @uri = uri
        @duration_ms = duration_ms
      end

      def artist_line
        artists.join(', ')
      end

      def display_label
        "#{title} - #{artist_line}"
      end
    end
  end
end
