# frozen_string_literal: true

module YouFM
  module Services
    module MusicSources
      class SpotifySource
        def initialize(client:)
          @client = client
        end

        def name = 'Spotify'

        def configured?
          client.configured?
        end

        def search_tracks(query)
          client.search_tracks(query)
        end

        def current_playback
          client.current_playback
        end

        def play_track(track)
          client.play_track(track.uri)
        end

        def pause
          client.pause
        end

        def resume
          client.resume
        end

        private

        attr_reader :client
      end
    end
  end
end
