# frozen_string_literal: true

module YouFM
  module ViewModels
    class MainViewModel
      PLAYLIST_PAGE_SIZE = 100
      DEFAULT_MINIMUM_RECOMMENDED_QUEUE_SIZE = 1

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
        :tracks_loading_more,
        :devices,
        :selected_device_index,
        :playlists,
        :selected_playlist_index,
        :queue_tracks,
        :selected_queue_index,
        :queue_recommendation_seeds,
        :status_message,
        :device_name,
        :now_playing,
        :recommendation_seed,
        :selected_queue_recommendation_seed,
        :playing
      )

      def initialize(source:, recommendation_coordinator:, recommendation_seed_store:, lastfm_authenticator:,
                     recommended_queue_store: nil)
        @source = source
        @recommendation_coordinator = recommendation_coordinator
        @recommendation_seed_store = recommendation_seed_store
        @lastfm_authenticator = lastfm_authenticator
        @last_playing_track_id = nil
        @minimum_recommended_queue_size = DEFAULT_MINIMUM_RECOMMENDED_QUEUE_SIZE
        @last_recommendation_seed_track_id = nil
        @now_playing_recommendation_seeds = {}
        @next_queue_refresh_at = nil
        initialize_state_notifier
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
          tracks_loading_more: false,
          devices: [],
          selected_device_index: nil,
          playlists: [],
          selected_playlist_index: nil,
          queue_tracks: [],
          selected_queue_index: nil,
          queue_recommendation_seeds: {},
          status_message: initial_status,
          device_name: nil,
          now_playing: 'No active playback',
          recommendation_seed: 'None',
          selected_queue_recommendation_seed: 'None',
          playing: false
        )
        @recommended_queue = RecommendedQueue.new(state: state, store: recommended_queue_store)
        @playlist_tracks_loader = PlaylistTracksLoader.new(
          state: state,
          source: source,
          page_size: PLAYLIST_PAGE_SIZE,
          update_status: method(:update_status),
          friendly_error_message: method(:friendly_error_message)
        )
      end

      attr_reader :state, :minimum_recommended_queue_size

      def revision
        @state_revision_mutex.synchronize { @state_revision }
      end

      def wait_for_revision(revision, timeout:)
        deadline = monotonic_time + timeout
        @state_revision_mutex.synchronize do
          while @state_revision <= revision
            remaining = deadline - monotonic_time
            break if remaining <= 0

            @state_condition.wait(@state_revision_mutex, remaining)
          end

          @state_revision
        end
      end

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
      rescue Services::SpotifyAuthenticator::Error, StandardError => e
        report_auth_failure('Spotify auth failed', e)
      end

      def connect_lastfm
        lastfm_authenticator.connect!
        sync_lastfm_connection_state!
        update_status('Last.fm authorization completed')
      rescue Services::LastfmAuthenticator::CallbackTimeoutError
        update_status('Timed out waiting for Last.fm authorization callback')
      rescue Services::LastfmAuthenticator::Error, StandardError => e
        report_auth_failure('Last.fm auth failed', e)
      end

      def disconnect_spotify
        source.disconnect!
        reset_spotify_session_state
        recommendation_coordinator.reset
        reset_view_state
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
        state.tracks_loading_more = false
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
        previous_track_id = @last_playing_track_id
        playback = source.current_playback
        state.device_name = playback.device_name.to_s.empty? ? active_device_name : playback.device_name
        state.now_playing = playback.status_label
        state.playing = playback.playing
        playback_change_message = handle_playback_track_change(playback.track, previous_track_id:)
        state.recommendation_seed = recommendation_seed_for_playback_track(playback.track) unless playback.track
        sync_connection_state!
        return if playback_change_message == :recommendation_queued

        update_status(playback_change_message || (state.connected ? 'Playback state updated' : initial_status))
      rescue Services::SpotifyClient::AuthenticationError
        sync_connection_state!
        update_status('Connect Spotify first')
      rescue StandardError => e
        update_status("Playback refresh failed: #{friendly_error_message(e)}")
      end

      def refresh_library
        load_library_snapshot
        refresh_queue
        refresh_playback
        align_selections
        update_status('Spotify library updated')
      rescue Services::SpotifyClient::AuthenticationError
        sync_connection_state!
        update_status('Connect Spotify first')
      rescue Services::SpotifyClient::PlaybackUnavailableError, Services::SpotifyClient::DeviceUnavailableError => e
        sync_connection_state!
        restore_library_snapshot
        state.queue_tracks = []
        update_status(friendly_error_message(e))
      rescue StandardError => e
        update_status("Library refresh failed: #{friendly_error_message(e)}")
      end

      def refresh_queue
        return state.queue_tracks if queue_refresh_deferred?

        refresh_queue_tracks!
        @next_queue_refresh_at = nil
      rescue Services::SpotifyClient::RateLimitedError => e
        schedule_queue_refresh_retry(e.retry_after_seconds)
        update_status(queue_rate_limit_message(e.retry_after_seconds))
      rescue Services::SpotifyClient::AuthenticationError
        update_status('Connect Spotify first')
      rescue StandardError => e
        update_status("Queue refresh failed: #{friendly_error_message(e)}")
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

      def select_playlist_index(index, &)
        return if index.nil?
        return if index.negative?
        return if index >= state.playlists.length

        state.selected_playlist_index = index
        playlist_tracks_loader.select(selected_playlist, &)
      end

      def select_queue_index(index)
        return if index.nil?
        return if index.negative?
        return if index >= state.queue_tracks.length

        state.selected_queue_index = index
        update_selected_queue_recommendation_seed
      end

      def play_selected
        track = selected_track
        return update_status('Select a track first') unless track

        source.play_track(track)
        remember_playing_track(track.id)
        schedule_recommendation_for_track(track)
        enqueue_recommendation_async(trigger: :manual)
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
        mark_device_active!(device.id)
        state.device_name = device.name
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
        remember_playing_track(track.id)
        remove_track_from_local_queue(track.id)
        schedule_recommendation_for_track(track)
        enqueue_recommendation_async(trigger: :manual)
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

      def generate_recommendation
        enqueue_recommendation(trigger: :manual)
      rescue StandardError => e
        update_status("Recommendation failed: #{friendly_error_message(e)}")
      end

      def generate_recommendation_async
        enqueue_recommendation_async(trigger: :manual)
      end

      def similar_artist_pool_limit
        recommendation_coordinator.similar_artist_pool_limit
      end

      def apply_similar_artist_pool_limit(value)
        parsed = normalize_similar_artist_pool_limit(value)
        return nil unless parsed

        recommendation_coordinator.similar_artist_pool_limit = parsed
        parsed
      end

      def update_similar_artist_pool_limit(value)
        parsed = apply_similar_artist_pool_limit(value)
        return update_status('Similar artist pool limit must be a positive integer') unless parsed

        update_status("Similar artist pool limit set to #{parsed}")
        parsed
      end

      def apply_minimum_recommended_queue_size(value)
        parsed = normalize_positive_integer(value)
        return nil unless parsed

        @minimum_recommended_queue_size = parsed
      end

      def update_minimum_recommended_queue_size(value)
        parsed = apply_minimum_recommended_queue_size(value)
        return update_status('Minimum recommended queue size must be a positive integer') unless parsed

        update_status("Minimum recommended queue size set to #{parsed}")
        parsed
      end

      def status=(message)
        update_status(message)
      end

      def load_more_playlist_tracks(&)
        playlist_tracks_loader.load_more(selected_playlist, &)
      end

      def refresh_playlist_loading_status
        playlist_tracks_loader.refresh_loading_status
      end

      private

      attr_reader :source, :recommendation_coordinator, :recommendation_seed_store, :lastfm_authenticator,
                  :playlist_tracks_loader, :recommended_queue

      def initialize_state_notifier
        @state_revision_mutex = Mutex.new
        @state_condition = ConditionVariable.new
        @state_revision = 0
      end

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

      def enqueue_recommendation(trigger:)
        recommendation_coordinator.enqueue(**recommendation_context(trigger))
      end

      def align_selections
        state.selected_device_index = first_active_device_index
        state.selected_playlist_index = 0 if state.selected_playlist_index.nil? && state.playlists.any?
      end

      def first_active_device_index
        state.devices.index(&:active) || (state.devices.empty? ? nil : 0)
      end

      def active_device_name
        state.devices.find(&:active)&.name
      end

      def mark_device_active!(device_id)
        state.devices = state.devices.map do |device|
          Models::Device.new(
            id: device.id,
            name: device.name,
            type: device.type,
            active: device.id == device_id,
            restricted: device.restricted
          )
        end
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

      def report_auth_failure(prefix, error)
        update_status("#{prefix}: #{error.message}")
      end

      def update_status(message)
        status_changed = state.status_message != message
        state.status_message = message if status_changed
        Services::Logger.info("[youfm] status: #{message}") if status_changed
        notify_state_changed

        message
      end

      def append_recommended_track_to_local_queue(track, seed_label)
        queue_size = recommended_queue.append(track, seed_label)
        enqueue_recommendation_async(trigger: :queue_fill) if queue_size < minimum_recommended_queue_size
      end

      def recommendation_seed_tracks
        state.search_results.reject { |track| track.id.to_s.empty? }
      end

      def recommendation_playlist_name
        selected_playlist&.name || state.tracks_title
      end

      def schedule_recommendation_for_track(track)
        @last_recommendation_seed_track_id = track.id.to_s
      end

      def recommendation_seed_for_playback_track(track)
        return 'None' unless track

        normalized_track_id = track.id.to_s
        seed = @now_playing_recommendation_seeds[normalized_track_id] ||
               recommendation_seed_store.fetch(normalized_track_id)
        @now_playing_recommendation_seeds[normalized_track_id] = seed if seed
        seed || 'None'
      end

      def handle_playback_track_change(track, previous_track_id:)
        current_track_id = track&.id.to_s
        return if current_track_id.empty?

        remember_playing_track(current_track_id)
        remember_now_playing_recommendation_seed(current_track_id)
        remove_track_from_local_queue(current_track_id)
        state.recommendation_seed = recommendation_seed_for_playback_track(track)
        return unless track_changed?(current_track_id, previous_track_id)
        return if @last_recommendation_seed_track_id == current_track_id

        schedule_recommendation_for_track(track)
        Services::Logger.info(
          "[youfm] playback track changed: previous=#{previous_track_id || 'none'} " \
          "current=#{current_track_id}; scheduling recommendation"
        )
        enqueue_recommendation_async(trigger: :playback_change)
        :recommendation_queued
      end

      def enqueue_recommendation_async(trigger:)
        recommendation_coordinator.enqueue_async(**recommendation_context(trigger))
      end

      def track_changed?(current_track_id, previous_track_id)
        previous_track_id.to_s != current_track_id
      end

      def remember_playing_track(track_id)
        normalized_track_id = track_id.to_s
        return if normalized_track_id.empty?

        @last_playing_track_id = normalized_track_id
        recommended_queue.remember_playing_track(normalized_track_id)
      end

      def remember_now_playing_recommendation_seed(track_id)
        recommended_queue.remember_now_playing_seed(track_id, @now_playing_recommendation_seeds)
      end

      def blocked_recommendation_track_ids
        recommended_queue.blocked_track_ids
      end

      def remove_track_from_local_queue(track_id)
        recommended_queue.remove(track_id)
      end

      def refresh_queue_tracks!
        recommended_queue.sync(source.queue)
      end

      def update_selected_queue_recommendation_seed
        recommended_queue.update_selected_seed!
      end

      def reset_spotify_session_state
        @last_playing_track_id = nil
        @last_recommendation_seed_track_id = nil
        @now_playing_recommendation_seeds = {}
        @next_queue_refresh_at = nil
        recommended_queue.clear
        playlist_tracks_loader.reset
      end

      def reset_view_state
        state.devices = []
        state.selected_device_index = nil
        state.playlists = []
        state.selected_playlist_index = nil
        state.queue_tracks = []
        state.queue_recommendation_seeds = {}
        state.search_results = []
        state.selected_index = nil
        state.tracks_loading_more = false
        state.tracks_title = 'Tracks'
        state.device_name = nil
        state.now_playing = 'No active playback'
        state.recommendation_seed = 'None'
        state.selected_queue_recommendation_seed = 'None'
        state.playing = false
      end

      def recommendation_context(trigger)
        {
          seed_tracks: recommendation_seed_tracks,
          excluded_track_ids: method(:blocked_recommendation_track_ids),
          playlist_name: recommendation_playlist_name,
          trigger: trigger,
          append_track: method(:append_recommended_track_to_local_queue),
          update_status: method(:update_status)
        }
      end

      def load_library_snapshot
        state.devices = source.available_devices
        state.playlists = source.playlists
      end

      def restore_library_snapshot
        state.devices = begin
          source.available_devices
        rescue StandardError
          []
        end
        state.playlists = begin
          source.playlists
        rescue StandardError
          []
        end
      end

      def normalize_similar_artist_pool_limit(value)
        normalize_positive_integer(value)
      end

      def normalize_positive_integer(value)
        parsed = Integer(value, exception: false)
        return nil if parsed.nil? || parsed <= 0

        parsed
      end

      def queue_refresh_deferred?
        @next_queue_refresh_at && Time.now < @next_queue_refresh_at
      end

      def schedule_queue_refresh_retry(retry_after_seconds)
        return unless retry_after_seconds&.positive?

        @next_queue_refresh_at = Time.now + retry_after_seconds
      end

      def queue_rate_limit_message(retry_after_seconds)
        return 'Queue refresh rate-limited by Spotify' unless retry_after_seconds&.positive?

        "Queue refresh rate-limited by Spotify, retrying in #{retry_after_seconds}s"
      end

      def notify_state_changed
        @state_revision_mutex.synchronize do
          @state_revision += 1
          @state_condition.broadcast
        end
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
