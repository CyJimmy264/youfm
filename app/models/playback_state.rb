# frozen_string_literal: true

module YouFM
  module Models
    class PlaybackState
      extend Props

      props :device_name, :track, :playing, :progress_ms

      def status_label
        return 'No active playback' unless track

        verb = playing ? 'Playing' : 'Paused'
        "#{verb}: #{track.display_label}"
      end
    end
  end
end
