# frozen_string_literal: true

module YouFM
  module Models
    class PlaybackState
      attr_reader :device_name, :track, :playing, :progress_ms

      def initialize(device_name:, track:, playing:, progress_ms:)
        @device_name = device_name
        @track = track
        @playing = playing
        @progress_ms = progress_ms
      end

      def status_label
        return 'No active playback' unless track

        verb = playing ? 'Playing' : 'Paused'
        "#{verb}: #{track.display_label}"
      end
    end
  end
end
