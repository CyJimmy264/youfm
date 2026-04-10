# frozen_string_literal: true

module YouFM
  module ViewModels
    class MainViewModel
      State = Struct.new(
        :source_name,
        :configured,
        :connected,
        :auth_status,
        :lastfm_connected,
        :lastfm_auth_status,
        :tracks_title,
        :search_query,
        :search_results,
        :selected_index,
        :devices,
        :selected_device_index,
        :playlists,
        :selected_playlist_index,
        :queue_tracks,
        :selected_queue_index,
        :status_message,
        :device_name,
        :now_playing,
        :playing,
        keyword_init: true
      )

      def initialize(source:, recommendation_generator:, lastfm_authenticator:)
        @source = source
        @recommendation_generator = recommendation_generator
        @lastfm_authenticator = lastfm_authenticator
        @queue_mutex = Mutex.new
        @state = State.new(
          source_name: source.name,
          configured: source.configured?,
          connected: source.connected?,
          auth_status: initial_auth_status,
          lastfm_connected: lastfm_connected?,
          lastfm_auth_status: initial_lastfm_auth_status,
          tracks_title: 'Tracks',
          search_query: '',
          search_results: [],
          selected_index: nil,
          devices: [],
          selected_device_index: nil,
          playlists: [],
          selected_playlist_index: nil,
          queue_tracks: [],
          selected_queue_index: nil,
          status_message: initial_status,
          device_name: nil,
          now_playing: 'No active playback',
          playing: false
        )
      end

      attr_reader :state

      def bootstrap
        sync_connection_state!
        sync_lastfm_connection_state!
        return update_status(initial_status) unless source.resumable_session?

        refresh_library
      rescue Services::SpotifyClient::AuthenticationError
        sync_connection_state!
        update_status('Saved Spotify session is no longer valid. Connect again.')
      rescue StandardError => e
        update_status("Startup sync failed: #{friendly_error_message(e)}")
      end

      def connect_spotify
        source.connect!
        sync_connection_state!
        refresh_library
        update_status('Spotify authorization completed')
      rescue Services::SpotifyAuthenticator::CallbackTimeoutError
        update_status('Timed out waiting for Spotify authorization callback')
      rescue Services::SpotifyAuthenticator::Error => e
        update_status("Spotify auth failed: #{e.message}")
      rescue StandardError => e
        update_status("Spotify auth failed: #{e.message}")
      end

      def connect_lastfm
        lastfm_authenticator.connect!
        sync_lastfm_connection_state!
        update_status('Last.fm authorization completed')
      rescue Services::LastfmAuthenticator::CallbackTimeoutError
        update_status('Timed out waiting for Last.fm authorization callback')
      rescue Services::LastfmAuthenticator::Error => e
        update_status("Last.fm auth failed: #{e.message}")
      rescue StandardError => e
        update_status("Last.fm auth failed: #{e.message}")
      end

      def disconnect_spotify
        source.disconnect!
        state.devices = []
        state.selected_device_index = nil
        state.playlists = []
        state.selected_playlist_index = nil
        state.queue_tracks = []
        state.search_results = []
        state.selected_index = nil
        state.tracks_title = 'Tracks'
        state.device_name = nil
        state.now_playing = 'No active playback'
        state.playing = false
        sync_connection_state!
        update_status('Spotify session cleared')
      rescue StandardError => e
        update_status("Disconnect failed: #{e.message}")
      end

      def disconnect_lastfm
        lastfm_authenticator.disconnect!
        sync_lastfm_connection_state!
        update_status('Last.fm session cleared')
      rescue StandardError => e
        update_status("Last.fm disconnect failed: #{e.message}")
      end

      def search(query)
        state.search_query = query.to_s.strip
        return update_status('Enter a search query') if state.search_query.empty?

        tracks = source.search_tracks(state.search_query)
        state.tracks_title = "Search Results for \"#{state.search_query}\""
        state.search_results = tracks
        state.selected_index = tracks.empty? ? nil : 0
        update_status(tracks.empty? ? 'No tracks found' : "Found #{tracks.length} tracks")
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue StandardError => e
        update_status("Search failed: #{e.message}")
      end

      def refresh_playback
        playback = source.current_playback
        state.device_name = playback.device_name
        state.now_playing = playback.status_label
        state.playing = playback.playing
        sync_connection_state!
        update_status(state.connected ? 'Playback state updated' : initial_status)
      rescue Services::SpotifyClient::AuthenticationError
        sync_connection_state!
        update_status('Connect Spotify first')
      rescue StandardError => e
        update_status("Playback refresh failed: #{friendly_error_message(e)}")
      end

      def refresh_library
        state.devices = source.available_devices
        state.playlists = source.playlists
        refresh_queue
        refresh_playback
        align_selections
        update_status('Spotify library updated')
      rescue Services::SpotifyClient::AuthenticationError
        sync_connection_state!
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        sync_connection_state!
        state.devices = source.available_devices rescue []
        state.playlists = source.playlists rescue []
        state.queue_tracks = []
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Library refresh failed: #{friendly_error_message(e)}")
      end

      def select_index(index)
        return if index.nil?
        return if index.negative?
        return if index >= state.search_results.length

        state.selected_index = index
      end

      def select_device_index(index)
        return if index.nil?
        return if index.negative?
        return if index >= state.devices.length

        state.selected_device_index = index
      end

      def select_playlist_index(index, &on_loaded)
        return if index.nil?
        return if index.negative?
        return if index >= state.playlists.length

        state.selected_playlist_index = index
        load_selected_playlist_tracks(&on_loaded)
      end

      def select_queue_index(index)
        return if index.nil?
        return if index.negative?
        return if index >= state.queue_tracks.length

        state.selected_queue_index = index
      end

      def play_selected
        track = selected_track
        return update_status('Select a track first') unless track

        source.play_track(track)
        Thread.new { enqueue_recommendation }
        state.playing = true
        state.now_playing = "Playing: #{track.display_label}"
        update_status('Playback command sent to Spotify')
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Play failed: #{friendly_error_message(e)}")
      end

      def activate_selected_device
        device = selected_device
        return update_status('Select a device first') unless device

        source.transfer_playback(device)
        refresh_library
        update_status("Transferred playback to #{device.name}")
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Device switch failed: #{friendly_error_message(e)}")
      end

      def play_selected_playlist
        playlist = selected_playlist
        return update_status('Select a playlist first') unless playlist

        source.play_playlist(playlist, device_id: selected_device&.id)
        state.playing = true
        update_status("Playlist queued for playback: #{playlist.name}")
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Playlist playback failed: #{friendly_error_message(e)}")
      end

      def play_selected_queued_track
        track = selected_queued_track
        return update_status('Select a track from the queue first') unless track

        source.play_track(track)
        Thread.new { enqueue_recommendation }
        state.playing = true
        state.now_playing = "Playing: #{track.display_label}"
        update_status('Playback command sent to Spotify')
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Play failed: #{friendly_error_message(e)}")
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
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Playback toggle failed: #{friendly_error_message(e)}")
      end

      def skip_to_next
        source.skip_to_next
        sleep 0.5 # Give Spotify a moment to update
        refresh_playback
        update_status('Skip command sent to Spotify')
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Skip failed: #{friendly_error_message(e)}")
      end

      private

      attr_reader :source, :recommendation_generator, :lastfm_authenticator

      def selected_track
        return nil if state.selected_index.nil?

        state.search_results[state.selected_index]
      end

      def selected_device
        return nil if state.selected_device_index.nil?

        state.devices[state.selected_device_index]
      end

      def selected_playlist
        return nil if state.selected_playlist_index.nil?

        state.playlists[state.selected_playlist_index]
      end

      def selected_queued_track
        return nil if state.selected_queue_index.nil?

        state.queue_tracks[state.selected_queue_index]
      end

      def refresh_queue
        @queue_mutex.synchronize do
          state.queue_tracks = source.queue
        end
      end

      def enqueue_recommendation
        seed_tracks = state.search_results
        recommended_track = recommendation_generator.generate_from_playlist(seed_tracks)
        return unless recommended_track

        # Prevent adding a recommendation if it's already in the queue
        return if state.queue_tracks.any? { |track| track.id == recommended_track.id }

        source.add_to_queue(recommended_track)
        refresh_queue
        update_status("Added recommendation to Spotify queue: #{recommended_track.display_label}")
      end

      def load_selected_playlist_tracks(&on_loaded)
        playlist = selected_playlist
        return unless playlist

        Thread.new do
          tracks = source.playlist_tracks(playlist)
          state.search_query = ''
          state.search_results = tracks
          state.selected_index = tracks.empty? ? nil : 0
          state.tracks_title = "Playlist: #{playlist.name}"
          update_status(tracks.empty? ? "Playlist is empty: #{playlist.name}" : "Loaded #{tracks.length} tracks from #{playlist.name}")
          on_loaded&.call
        rescue Services::SpotifyClient::AuthenticationError
          update_status('Connect Spotify first')
          on_loaded&.call
        rescue StandardError => e
          update_status("Playlist tracks failed: #{friendly_error_message(e)}")
          on_loaded&.call
        end
      end

      def align_selections
        state.selected_device_index = first_active_device_index
        state.selected_playlist_index = 0 if state.selected_playlist_index.nil? && state.playlists.any?
      end

      def first_active_device_index
        state.devices.index(&:active) || (state.devices.empty? ? nil : 0)
      end

      def initial_status
        return 'Ready' if source.connected?
        return 'Restoring saved Spotify session' if source.resumable_session?
        return 'Connect Spotify to continue' if source.configured?

        'Set SPOTIFY_CLIENT_ID and SPOTIFY_REDIRECT_URI to use Spotify OAuth'
      end

      def initial_auth_status
        return 'Connected to Spotify' if source.connected?
        return 'Saved Spotify session found' if source.resumable_session?
        return 'Spotify OAuth is ready' if source.configured?

        'Spotify OAuth is not configured'
      end

      def initial_lastfm_auth_status
        return 'Connected to Last.fm' if lastfm_connected?
        return 'Ready to connect Last.fm' if lastfm_configured?

        'Last.fm is not configured'
      end

      def sync_connection_state!
        state.configured = source.configured?
        state.connected = source.connected?
        state.auth_status =
          if state.connected
            'Connected to Spotify'
          elsif source.resumable_session?
            'Saved session available'
          elsif state.configured
            'Ready to connect'
          else
            'OAuth is not configured'
          end
      end

      def sync_lastfm_connection_state!
        state.lastfm_connected = lastfm_connected?
        state.lastfm_auth_status =
          if lastfm_connected?
            'Connected to Last.fm'
          elsif lastfm_configured?
            'Ready to connect Last.fm'
          else
            'Last.fm is not configured'
          end
      end

      def lastfm_connected?
        lastfm_authenticator.connected?
      end

      def lastfm_configured?
        lastfm_authenticator.configured?
      end

      def friendly_error_message(error)
        case error
        when Services::SpotifyClient::PlaybackUnavailableError
          'Spotify playback is unavailable. Start Spotify on a Premium device and try again.'
        when Services::SpotifyClient::DeviceUnavailableError
          'No active Spotify device is available. Open Spotify on a device first.'
        else
          error.message
        end
      end

      def update_status(message)
        state.status_message = message
      end
    end
  end
end
