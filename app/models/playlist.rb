# frozen_string_literal: true

module YouFM
  module Models
    class Playlist
      attr_reader :id, :name, :uri, :owner_name, :tracks_total, :snapshot_id

      def initialize(id:, name:, uri:, owner_name:, tracks_total:, snapshot_id: nil)
        @id = id
        @name = name
        @uri = uri
        @owner_name = owner_name
        @tracks_total = tracks_total
        @snapshot_id = snapshot_id
      end

      def display_label
        "#{name} · #{owner_name} · #{tracks_total} tracks"
      end
    end
  end
end
