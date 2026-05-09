# frozen_string_literal: true

module YouFM
  module Models
    class Playlist
      extend Props

      props :id, :name, :uri, :owner_name, :tracks_total, snapshot_id: nil

      def display_label
        "#{name} · #{owner_name} · #{tracks_total} tracks"
      end
    end
  end
end
