# frozen_string_literal: true

module YouFM
  module Views
    class MainWindow
      WINDOW_W = 1260
      WINDOW_H = 840
      ACTIVE_PLAYBACK_REFRESH_MS = 20_000
      IDLE_PLAYBACK_REFRESH_MS = 30_000
      IDLE_POLLS_BEFORE_SUSPEND = 2
      UI_REFRESH_MS = 100
      THEMES = %w[dark light].freeze
      LOADER_FRAMES = ['Loading   ', 'Loading.  ', 'Loading.. ', 'Loading...'].freeze

      def initialize(
        view_model:,
        theme: Styles::Theme.new(name: 'dark'),
        settings_store: Models::NullSettingsStore.new
      )
        @view_model = view_model
        @theme = theme
        @settings_store = settings_store
        @shutdown_requested = false
        @render_queue = Queue.new
        @loader_frame_index = 0
        @idle_playback_polls = 0
        @last_seen_state_revision = nil
        @last_rendered_tracks_signature = nil
        build_window
        bind_events
        apply_saved_similar_artist_pool_limit
        view_model.bootstrap
        render_full
        @last_seen_state_revision = view_model.revision
        force_active_playback_polling!
      end

      def show = window.show

      def request_shutdown = @shutdown_requested = true

      private

      attr_reader :view_model, :theme, :settings_store, :window, :search_input, :results_list, :playlists_list,
                  :queue_list, :device_picker, :status_label, :auth_label, :lastfm_auth_label, :device_label,
                  :now_playing_label, :recommendation_seed_label, :toggle_button, :theme_button, :connect_button,
                  :disconnect_button, :connect_lastfm_button, :disconnect_lastfm_button, :tracks_title_label,
                  :next_button, :similar_artist_pool_limit_input

      def build_window
        @window = QWidget.new do |widget|
          widget.object_name = 'main_window'
          widget.window_title = 'YouFM'
          widget.set_geometry(60, 60, WINDOW_W, WINDOW_H)
          widget.style_sheet = theme.application_stylesheet
        end

        build_window_layout
        start_timers
      end

      def build_window_layout
        root = QVBoxLayout.new(window)
        root.set_contents_margins(24, 24, 24, 24)
        root.spacing = 16

        root.add_widget(build_header)
        root.add_layout(build_auth_row)
        root.add_layout(build_search_row)
        root.add_layout(build_actions_row)
        root.add_layout(build_content_row)
        root.add_widget(build_devices_panel)
        root.add_widget(build_footer)
      end

      def start_timers
        @ui_updater = QTimer.new(window)
        @ui_updater.interval = UI_REFRESH_MS
        @ui_updater.connect('timeout') { on_ui_update }
        @ui_updater.start

        @playback_refresher = QTimer.new(window)
        @playback_refresher.interval = ACTIVE_PLAYBACK_REFRESH_MS
        @playback_refresher.connect('timeout') { on_playback_refresh }
        @playback_refresher.start
      end

      def build_header
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 4

          layout.add_widget(build_label(widget, 'hero_title', 'YouFM'))
          layout.add_widget(build_label(widget, 'hero_subtitle', 'Spotify-first desktop player on Ruby + Qt'))
        end
      end

      def build_auth_row
        QHBoxLayout.new.tap do |layout|
          @connect_button = build_button(window, 'primary_button', 'Connect Spotify')
          connect_button.connect('clicked') { |_| handle_connect_spotify }
          layout.add_widget(connect_button)

          @disconnect_button = build_button(window, 'ghost_button', 'Disconnect')
          disconnect_button.connect('clicked') { |_| handle_disconnect_spotify }
          layout.add_widget(disconnect_button)

          @connect_lastfm_button = build_button(window, 'primary_button', 'Connect Last.fm')
          @disconnect_lastfm_button = build_button(window, 'ghost_button', 'Disconnect')

          layout.add_widget(connect_lastfm_button)
          layout.add_widget(disconnect_lastfm_button)

          refresh_button = build_button(window, 'ghost_button', 'Sync Library')
          refresh_button.connect('clicked') { |_| handle_refresh_library }
          layout.add_widget(refresh_button)

          layout.add_stretch(1)
        end
      end

      def build_search_row
        QHBoxLayout.new.tap do |layout|
          @search_input = QLineEdit.new(window)
          search_input.object_name = 'search_input'
          search_input.placeholder_text = 'Search tracks on Spotify'
          layout.add_widget(search_input, 1)

          search_button = build_button(window, 'primary_button', 'Search')
          search_button.connect('clicked') { |_| handle_search }
          layout.add_widget(search_button)
        end
      end

      def build_actions_row
        QHBoxLayout.new.tap do |layout|
          add_playback_controls(layout)
          add_artist_pool_controls(layout)
          add_secondary_controls(layout)

          layout.add_stretch(1)
        end
      end

      def add_playback_controls(layout)
        play_button = build_button(window, 'primary_button', 'Play Selected')
        play_button.connect('clicked') { |_| handle_play_selected }
        layout.add_widget(play_button)

        @toggle_button = build_button(window, 'ghost_button', 'Resume')
        toggle_button.connect('clicked') { |_| handle_toggle }
        layout.add_widget(toggle_button)

        @next_button = build_button(window, 'ghost_button', 'Next')
        layout.add_widget(next_button)

        generate_button = build_button(window, 'ghost_button', 'Generate Next')
        generate_button.connect('clicked') { |_| handle_generate_recommendation }
        layout.add_widget(generate_button)
      end

      def add_artist_pool_controls(layout)
        layout.add_widget(build_label(window, 'status_label', 'Artist Pool'))

        @similar_artist_pool_limit_input = QLineEdit.new(window)
        similar_artist_pool_limit_input.object_name = 'search_input'
        similar_artist_pool_limit_input.placeholder_text = 'Pool limit'
        similar_artist_pool_limit_input.maximum_width = 96
        similar_artist_pool_limit_input.text = view_model.similar_artist_pool_limit.to_s
        layout.add_widget(similar_artist_pool_limit_input)

        apply_pool_limit_button = build_button(window, 'ghost_button', 'Apply')
        apply_pool_limit_button.connect('clicked') { |_| handle_apply_similar_artist_pool_limit }
        layout.add_widget(apply_pool_limit_button)
      end

      def add_secondary_controls(layout)
        refresh_button = build_button(window, 'ghost_button', 'Refresh')
        refresh_button.connect('clicked') { |_| handle_refresh }
        layout.add_widget(refresh_button)

        @theme_button = build_button(window, 'ghost_button', 'Theme')
        theme_button.connect('clicked') { |_| handle_switch_theme }
        layout.add_widget(theme_button)
      end

      def build_content_row
        QHBoxLayout.new.tap do |layout|
          layout.spacing = 16
          layout.add_widget(build_tracks_panel, 1)
          layout.add_widget(build_playlists_panel, 1)
          layout.add_widget(build_queue_panel, 1)
        end
      end

      def build_tracks_panel
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 8
          @tracks_title_label = build_label(widget, 'section_label', 'Tracks')
          layout.add_widget(tracks_title_label)
          layout.add_widget(build_results_list, 1)
        end
      end

      def build_playlists_panel
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 10

          layout.add_widget(build_label(widget, 'section_label', 'Playlists'))
          layout.add_widget(build_playlists_list, 1)

          playlist_button = build_button(widget, 'ghost_button', 'Play Playlist')
          playlist_button.connect('clicked') { |_| handle_play_playlist }
          layout.add_widget(playlist_button)
        end
      end

      def build_queue_panel
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 10
          layout.add_widget(build_label(widget, 'section_label', 'Queue'))
          layout.add_widget(build_queue_list, 1)
        end
      end

      def build_devices_panel
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 10
          layout.add_widget(build_label(widget, 'section_label', 'Devices'))
          layout.add_layout(build_device_row)
        end
      end

      def build_device_row
        QHBoxLayout.new.tap do |layout|
          @device_picker = QComboBox.new(window)
          device_picker.object_name = 'device_picker'
          layout.add_widget(device_picker, 1)

          device_button = build_button(window, 'ghost_button', 'Use Device')
          device_button.connect('clicked') { |_| handle_activate_device }
          layout.add_widget(device_button)
        end
      end

      def build_results_list
        @results_list = QListWidget.new(window)
        results_list.object_name = 'results_list'
        results_list
      end

      def build_playlists_list
        @playlists_list = QListWidget.new(window)
        playlists_list.object_name = 'results_list'
        playlists_list
      end

      def build_queue_list
        @queue_list = QListWidget.new(window)
        queue_list.object_name = 'results_list'
        queue_list
      end

      def build_footer
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          @auth_label = build_label(widget, 'status_label', '')
          @lastfm_auth_label = build_label(widget, 'status_label', '')
          @status_label = build_label(widget, 'status_label', '')
          @device_label = build_label(widget, 'device_label', '')
          @now_playing_label = build_label(widget, 'now_playing_label', '')
          make_label_selectable(now_playing_label)
          @recommendation_seed_label = build_label(widget, 'recommendation_seed_label', '')
          make_label_selectable(recommendation_seed_label)
          layout.add_widget(auth_label)
          layout.add_widget(lastfm_auth_label)
          layout.add_widget(status_label)
          layout.add_widget(device_label)
          layout.add_widget(now_playing_label)
          layout.add_widget(recommendation_seed_label)
        end
      end

      def build_label(parent, object_name, text)
        QLabel.new(parent).tap do |label|
          label.object_name = object_name
          label.text = text
        end
      end

      def make_label_selectable(label)
        flags = Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard
        label.text_interaction_flags = flags
      rescue NoMethodError
        label.text_interaction_flags = flags
      end

      def build_button(parent, object_name, text)
        QPushButton.new(parent).tap do |button|
          button.object_name = object_name
          button.text = text
          button.focus_policy = Qt::NoFocus
          button.cursor = Qt::PointingHandCursor
        end
      end

      def bind_events
        search_input.connect('returnPressed()') { handle_search }
        similar_artist_pool_limit_input.connect('returnPressed()') { handle_apply_similar_artist_pool_limit }
        results_list.connect('currentRowChanged(int)') { |index| handle_selection(index) }
        results_list.connect('itemDoubleClicked(QListWidgetItem*)') { |_| handle_play_selected }
        results_list.verticalScrollBar.connect('valueChanged(int)') { |_| handle_results_scroll }
        playlists_list.connect('currentRowChanged(int)') { |index| handle_playlist_selection(index) }
        playlists_list.connect('itemDoubleClicked(QListWidgetItem*)') { |_| handle_play_playlist }
        queue_list.connect('currentRowChanged(int)') { |index| handle_queue_selection(index) }
        queue_list.connect('itemDoubleClicked(QListWidgetItem*)') { |_| handle_play_queued }
        device_picker.connect('currentIndexChanged(int)') { |index| handle_device_selection(index) }
        connect_lastfm_button.connect('clicked') { |_| handle_connect_lastfm }
        disconnect_lastfm_button.connect('clicked') { |_| handle_disconnect_lastfm }
        next_button.connect('clicked') { |_| handle_skip_to_next }
      end

      def handle_connect_spotify
        resume_playback_polling!
        view_model.connect_spotify
        render_full
      end

      def handle_connect_lastfm
        view_model.connect_lastfm
        render_full
      end

      def handle_search
        view_model.search(search_input.text.to_s)
        render_full
      end

      def handle_disconnect_spotify
        view_model.disconnect_spotify
        suspend_playback_polling!
        render_full
      end

      def handle_disconnect_lastfm
        view_model.disconnect_lastfm
        render_full
      end

      def handle_selection(_index)
        index = results_list.currentRow
        view_model.select_index(index.to_i)
        render_status
      end

      def handle_results_scroll
        scrollbar = results_list.verticalScrollBar
        return unless scrollbar
        return unless scrollbar.maximum.positive?
        return unless scrollbar.value >= scrollbar.maximum - 20

        view_model.load_more_playlist_tracks { @render_queue.push(:render_tracks) }
      end

      def handle_queue_selection(_index)
        index = queue_list.currentRow
        view_model.select_queue_index(index.to_i)
        render_status
      end

      def handle_device_selection(index)
        view_model.select_device_index(index.to_i)
      end

      def handle_playlist_selection(_index)
        index = playlists_list.currentRow
        @render_queue.push(:render_full)
        view_model.select_playlist_index(index.to_i) { @render_queue.push(:render_tracks) }
      end

      def handle_play_selected
        resume_playback_polling!
        view_model.play_selected
        render_status
      end

      def handle_play_queued
        resume_playback_polling!
        view_model.play_selected_queued_track
        render_status
      end

      def handle_activate_device
        resume_playback_polling!
        view_model.activate_selected_device
        render_full
      end

      def handle_play_playlist
        resume_playback_polling!
        view_model.play_selected_playlist
        render_status
      end

      def handle_toggle
        resume_playback_polling!
        view_model.toggle_playback
        render_status
      end

      def handle_skip_to_next
        resume_playback_polling!
        view_model.skip_to_next
        render_status
      end

      def handle_generate_recommendation
        resume_playback_polling!
        view_model.generate_recommendation
        render_status
      end

      def handle_apply_similar_artist_pool_limit
        applied_limit = view_model.update_similar_artist_pool_limit(similar_artist_pool_limit_input.text.to_s)
        if applied_limit
          similar_artist_pool_limit_input.text = applied_limit.to_s
          settings_store.write_similar_artist_pool_limit(applied_limit)
        else
          similar_artist_pool_limit_input.text = view_model.similar_artist_pool_limit.to_s
        end
        render_status
      rescue StandardError => e
        Services::Logger.warn("[youfm] save similar artist pool limit failed: #{e.class}: #{e.message}")
      end

      def handle_refresh
        force_active_playback_polling!
        view_model.refresh_playback
        render_status
      end

      def handle_refresh_library
        resume_playback_polling!
        view_model.refresh_library
        render_full
      end

      def handle_switch_theme
        current_index = THEMES.index(theme.name) || 0
        next_theme = Styles::Theme.new(name: THEMES[(current_index + 1) % THEMES.length])
        @theme = next_theme
        window.style_sheet = theme.application_stylesheet
        settings_store.write_theme_name(theme.name)
        render_full
      rescue StandardError => e
        Services::Logger.warn("[youfm] save theme failed: #{e.class}: #{e.message}")
      end

      def on_ui_update
        close_if_requested and return if @shutdown_requested

        enqueue_external_state_render

        if view_model.state.tracks_loading_more
          view_model.refresh_playlist_loading_status
          @loader_frame_index = (@loader_frame_index + 1) % LOADER_FRAMES.length
          @render_queue.push(:render_tracks) if @render_queue.empty?
        end

        until @render_queue.empty?
          message = @render_queue.pop(true)
          case message
          when :render_full
            render_full
          when :render_tracks
            adjust_playback_polling!
            render_tracks
          when :render_playback
            adjust_playback_polling!
            render_playback
          end
        end
      end

      def on_playback_refresh
        view_model.refresh_playback
        adjust_playback_polling!
        @render_queue.push(:render_playback)
      rescue StandardError => e
        Services::Logger.warn("[youfm] playback refresh failed: #{e.class}: #{e.message}")
        @render_queue.push(:render_playback)
      end

      def close_if_requested
        @ui_updater.stop if @ui_updater.is_active
        @playback_refresher.stop if @playback_refresher.is_active
        window.close
      end

      def adjust_playback_polling!
        if playback_inactive?
          @idle_playback_polls += 1
          if @idle_playback_polls >= IDLE_POLLS_BEFORE_SUSPEND
            suspend_playback_polling!
          else
            @playback_refresher.interval = IDLE_PLAYBACK_REFRESH_MS
          end
        else
          @idle_playback_polls = 0
          @playback_refresher.interval = ACTIVE_PLAYBACK_REFRESH_MS
          @playback_refresher.start unless @playback_refresher.is_active
        end
      end

      def playback_inactive?
        state = view_model.state
        !state.playing && state.now_playing == 'No active playback'
      end

      def resume_playback_polling!
        @idle_playback_polls = 0
        @playback_refresher.interval = ACTIVE_PLAYBACK_REFRESH_MS
        @playback_refresher.start unless @playback_refresher.is_active
      end

      def force_active_playback_polling!
        @idle_playback_polls = 0
        @playback_refresher.interval = ACTIVE_PLAYBACK_REFRESH_MS
        @playback_refresher.start unless @playback_refresher.is_active
      end

      def suspend_playback_polling!
        @idle_playback_polls = IDLE_POLLS_BEFORE_SUSPEND
        @playback_refresher.stop if @playback_refresher.is_active
      end

      def apply_saved_similar_artist_pool_limit
        saved_limit = settings_store.read_similar_artist_pool_limit
        return similar_artist_pool_limit_input.text = view_model.similar_artist_pool_limit.to_s if saved_limit.nil?

        applied_limit = view_model.update_similar_artist_pool_limit(saved_limit.to_s)
        similar_artist_pool_limit_input.text = (applied_limit || view_model.similar_artist_pool_limit).to_s
      rescue StandardError => e
        Services::Logger.warn("[youfm] load similar artist pool limit failed: #{e.class}: #{e.message}")
        similar_artist_pool_limit_input.text = view_model.similar_artist_pool_limit.to_s
      end

      def render_full
        state = view_model.state
        render_results(state)
        render_devices(state)
        render_playlists(state)
        render_queue(state)
        render_status
      end

      def render_tracks
        state = view_model.state
        render_results(state)
        render_status
      end

      def render_playback
        state = view_model.state
        render_queue(state)
        render_status
      end

      def render_status
        state = view_model.state
        tracks_title_label.text = state.tracks_title
        toggle_button.text = state.playing ? 'Pause' : 'Resume'
        theme_button.text = "Theme: #{theme.name.upcase}"
        connect_button.text = state.connected ? 'Spotify Connected' : 'Connect Spotify'
        connect_button.enabled = !state.connected
        disconnect_button.enabled = state.connected
        connect_lastfm_button.text = state.lastfm_connected ? 'Last.fm Connected' : 'Connect Last.fm'
        connect_lastfm_button.enabled = !state.lastfm_connected
        disconnect_lastfm_button.enabled = state.lastfm_connected
        auth_label.text = "Auth: #{state.auth_status}"
        lastfm_auth_label.text = "Last.fm Auth: #{state.lastfm_auth_status}"
        status_label.text = "Status: #{state.status_message}"
        device_label.text = state.device_name.to_s.empty? ? 'Device: no active device' : "Device: #{state.device_name}"
        now_playing_label.text = "Now: #{state.now_playing}"
        recommendation_seed_label.text = "Recommendation Seed: #{displayed_recommendation_seed(state)}"
      end

      def displayed_recommendation_seed(state)
        state.recommendation_seed
      end

      def render_results(state)
        scrollbar = results_list.verticalScrollBar
        previous_scroll_value = scrollbar&.value
        results_list.block_signals(true)
        results_list.clear
        state.search_results.each do |track|
          results_list.add_item(track.display_label)
        end
        results_list.add_item(loader_item_text) if state.tracks_loading_more
        results_list.current_row = state.selected_index if state.selected_index
        results_list.block_signals(false)
        @last_rendered_tracks_signature = tracks_signature(state)
        return unless scrollbar && !previous_scroll_value.nil?

        scrollbar.value = [previous_scroll_value, scrollbar.maximum].min
      end

      def enqueue_external_state_render
        revision = view_model.revision
        return if revision == @last_seen_state_revision

        @last_seen_state_revision = revision
        if tracks_signature(view_model.state) == @last_rendered_tracks_signature
          render_status
        else
          @render_queue.push(:render_tracks)
        end
      end

      def tracks_signature(state)
        tracks = state.search_results
        [
          state.tracks_title,
          tracks.length,
          tracks.first&.id,
          tracks.last&.id,
          state.selected_index,
          state.tracks_loading_more
        ]
      end

      def loader_item_text
        LOADER_FRAMES[@loader_frame_index]
      end

      def render_devices(state)
        device_picker.block_signals(true)
        device_picker.clear
        state.devices.each { |device| device_picker.add_item(device.display_label) }
        device_picker.current_index = state.selected_device_index if state.selected_device_index
        device_picker.block_signals(false)
      end

      def render_playlists(state)
        playlists_list.block_signals(true)
        playlists_list.clear
        state.playlists.each do |playlist|
          playlists_list.add_item(playlist.display_label)
        end
        playlists_list.current_row = state.selected_playlist_index if state.selected_playlist_index
        playlists_list.block_signals(false)
      end

      def render_queue(state)
        queue_list.block_signals(true)
        queue_list.clear
        state.queue_tracks.each do |track|
          queue_list.add_item(track.display_label)
        end
        queue_list.current_row = state.selected_queue_index if state.selected_queue_index
        queue_list.block_signals(false)
      end
    end
  end
end
