# frozen_string_literal: true

module YouFM
  module Views
    class MainWindow
      WINDOW_W = 1120
      WINDOW_H = 760
      REFRESH_MS = 5_000
      THEMES = %w[dark light].freeze

      def initialize(
        view_model: ViewModels::MainViewModel.new(source: Services::MusicSources::SpotifySource.new(client: Services::SpotifyClient.new(access_token: nil))),
        theme: Styles::Theme.new(name: 'dark'),
        settings_store: Models::NullSettingsStore.new
      )
        @view_model = view_model
        @theme = theme
        @settings_store = settings_store
        @shutdown_requested = false
        build_window
        bind_events
        render
        view_model.refresh_playback
        render
      end

      def show = window.show

      def request_shutdown = @shutdown_requested = true

      private

      attr_reader :view_model, :theme, :settings_store, :window, :search_input, :results_list,
                  :status_label, :device_label, :now_playing_label, :toggle_button, :theme_button,
                  :heartbeat

      def build_window
        @window = QWidget.new do |widget|
          widget.object_name = 'main_window'
          widget.window_title = 'YouFM'
          widget.set_geometry(60, 60, WINDOW_W, WINDOW_H)
          widget.style_sheet = theme.application_stylesheet
        end

        root = QVBoxLayout.new(window)
        root.set_contents_margins(24, 24, 24, 24)
        root.spacing = 16

        root.add_widget(build_header)
        root.add_layout(build_search_row)
        root.add_layout(build_actions_row)
        root.add_widget(build_results_list)
        root.add_widget(build_footer)

        @heartbeat = QTimer.new(window)
        heartbeat.interval = REFRESH_MS
        heartbeat.connect('timeout') { |_| on_tick }
        heartbeat.start
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
          play_button = build_button(window, 'primary_button', 'Play Selected')
          play_button.connect('clicked') { |_| handle_play_selected }
          layout.add_widget(play_button)

          @toggle_button = build_button(window, 'ghost_button', 'Resume')
          toggle_button.connect('clicked') { |_| handle_toggle }
          layout.add_widget(toggle_button)

          refresh_button = build_button(window, 'ghost_button', 'Refresh')
          refresh_button.connect('clicked') { |_| handle_refresh }
          layout.add_widget(refresh_button)

          @theme_button = build_button(window, 'ghost_button', 'Theme')
          theme_button.connect('clicked') { |_| handle_switch_theme }
          layout.add_widget(theme_button)

          layout.add_stretch(1)
        end
      end

      def build_results_list
        @results_list = QListWidget.new(window)
        results_list.object_name = 'results_list'
        results_list.on(:mouse_double_click) { |_| handle_play_selected }
        results_list
      end

      def build_footer
        QWidget.new(window).tap do |widget|
          layout = QVBoxLayout.new(widget)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          @status_label = build_label(widget, 'status_label', '')
          @device_label = build_label(widget, 'device_label', '')
          @now_playing_label = build_label(widget, 'now_playing_label', '')
          layout.add_widget(status_label)
          layout.add_widget(device_label)
          layout.add_widget(now_playing_label)
        end
      end

      def build_label(parent, object_name, text)
        QLabel.new(parent).tap do |label|
          label.object_name = object_name
          label.text = text
        end
      end

      def build_button(parent, object_name, text)
        QPushButton.new(parent).tap do |button|
          button.object_name = object_name
          button.text = text
          button.focus_policy = Qt::NoFocus
        end
      end

      def bind_events
        search_input.connect('returnPressed()') { handle_search }
        results_list.connect('currentRowChanged(int)') { |index| handle_selection(index) }
      end

      def handle_search
        view_model.search(search_input.text.to_s)
        render
      end

      def handle_selection(index)
        view_model.select_index(index.to_i)
        render
      end

      def handle_play_selected
        view_model.play_selected
        render
      end

      def handle_toggle
        view_model.toggle_playback
        render
      end

      def handle_refresh
        view_model.refresh_playback
        render
      end

      def handle_switch_theme
        current_index = THEMES.index(theme.name) || 0
        next_theme = Styles::Theme.new(name: THEMES[(current_index + 1) % THEMES.length])
        @theme = next_theme
        window.style_sheet = theme.application_stylesheet
        settings_store.write_theme_name(theme.name)
        render
      rescue StandardError => e
        warn("[youfm] save theme failed: #{e.class}: #{e.message}")
      end

      def on_tick
        close_if_requested and return if @shutdown_requested

        view_model.refresh_playback
        render
      end

      def close_if_requested
        heartbeat.stop if heartbeat.is_active
        window.close
      end

      def render
        state = view_model.state
        render_results(state)
        toggle_button.text = state.playing ? 'Pause' : 'Resume'
        theme_button.text = "Theme: #{theme.name.upcase}"
        status_label.text = "Status: #{state.status_message}"
        device_label.text = state.device_name.to_s.empty? ? 'Device: no active device' : "Device: #{state.device_name}"
        now_playing_label.text = "Now: #{state.now_playing}"
      end

      def render_results(state)
        results_list.clear
        state.search_results.each do |track|
          item = QListWidgetItem.new(track.display_label)
          results_list.add_item(item)
        end
        results_list.current_row = state.selected_index if state.selected_index
      end
    end
  end
end
