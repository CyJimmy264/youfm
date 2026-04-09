# frozen_string_literal: true

module YouFM
  module ViewModels
    class MainViewModel
      State = Struct.new(
        :source_name,
        :configured,
        :search_query,
        :search_results,
        :selected_index,
        :status_message,
        :device_name,
        :now_playing,
        :playing,
        keyword_init: true
      )

      def initialize(source:)
        @source = source
        @state = State.new(
          source_name: source.name,
          configured: source.configured?,
          search_query: '',
          search_results: [],
          selected_index: nil,
          status_message: initial_status,
          device_name: nil,
          now_playing: 'No active playback',
          playing: false
        )
      end

      attr_reader :state

      def search(query)
        state.search_query = query.to_s.strip
        return update_status('Enter a search query') if state.search_query.empty?

        tracks = source.search_tracks(state.search_query)
        state.search_results = tracks
        state.selected_index = tracks.empty? ? nil : 0
        update_status(tracks.empty? ? 'No tracks found' : "Found #{tracks.length} tracks")
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Set SPOTIFY_ACCESS_TOKEN to use Spotify')
      rescue StandardError => e
        update_status("Search failed: #{e.message}")
      end

      def refresh_playback
        playback = source.current_playback
        state.device_name = playback.device_name
        state.now_playing = playback.status_label
        state.playing = playback.playing
        update_status(state.configured ? 'Playback state updated' : initial_status)
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Set SPOTIFY_ACCESS_TOKEN to use Spotify')
      rescue StandardError => e
        update_status("Playback refresh failed: #{e.message}")
      end

      def select_index(index)
        return if index.nil?
        return if index.negative?
        return if index >= state.search_results.length

        state.selected_index = index
      end

      def play_selected
        track = selected_track
        return update_status('Select a track first') unless track

        source.play_track(track)
        state.playing = true
        state.now_playing = "Playing: #{track.display_label}"
        update_status('Playback command sent to Spotify')
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Set SPOTIFY_ACCESS_TOKEN to use Spotify')
      rescue StandardError => e
        update_status("Play failed: #{e.message}")
      end

      def toggle_playback
        if state.playing
          source.pause
          state.playing = false
          update_status('Pause command sent to Spotify')
        else
          source.resume
          state.playing = true
          update_status('Resume command sent to Spotify')
        end
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Set SPOTIFY_ACCESS_TOKEN to use Spotify')
      rescue StandardError => e
        update_status("Playback toggle failed: #{e.message}")
      end

      private

      attr_reader :source

      def selected_track
        return nil if state.selected_index.nil?

        state.search_results[state.selected_index]
      end

      def initial_status
        source.configured? ? 'Ready' : 'Spotify token is not configured'
      end

      def update_status(message)
        state.status_message = message
      end
    end
  end
end
