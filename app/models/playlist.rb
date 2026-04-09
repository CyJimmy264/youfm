# frozen_string_literal: true

module YouFM
  module Models
    class Playlist
      attr_reader :id, :name, :uri, :owner_name, :tracks_total

      def initialize(id:, name:, uri:, owner_name:, tracks_total:)
        @id = id
        @name = name
        @uri = uri
        @owner_name = owner_name
        @tracks_total = tracks_total
      end

      def display_label
        "#{name} · #{owner_name} · #{tracks_total} tracks"
      end
    end
  end
end
