# frozen_string_literal: true

module YouFM
  module Views
    class TracksPanel
      LOADER_FRAMES = ['Loading   ', 'Loading.  ', 'Loading.. ', 'Loading...'].freeze
      SCROLL_LOAD_THRESHOLD = 20

      attr_reader :widget

      def initialize(parent:)
        @widget = QWidget.new(parent)
        @loader_frame_index = 0
        @last_rendered_signature = nil
        build_layout
      end

      def on_selection(&)
        list.connect('currentRowChanged(int)', &)
      end

      def on_double_click(&)
        list.connect('itemDoubleClicked(QListWidgetItem*)') { |_| yield }
      end

      def on_scroll_near_bottom(&)
        list.verticalScrollBar.connect('valueChanged(int)') { |_| yield if scrolled_near_bottom? }
      end

      def selected_index
        list.currentRow.to_i
      end

      def animate_loader_frame
        @loader_frame_index = (@loader_frame_index + 1) % LOADER_FRAMES.length
      end

      def render_status(state)
        title_label.text = state.tracks_title
      end

      def render(state)
        scrollbar = list.verticalScrollBar
        previous_scroll_value = scrollbar&.value
        render_items(state)
        @last_rendered_signature = signature(state)
        return unless scrollbar && !previous_scroll_value.nil?

        scrollbar.value = [previous_scroll_value, scrollbar.maximum].min
      end

      def rendered_current?(state)
        signature(state) == @last_rendered_signature
      end

      private

      attr_reader :list, :title_label

      def build_layout
        layout = QVBoxLayout.new(widget)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.spacing = 8

        @title_label = QLabel.new(widget)
        title_label.object_name = 'section_label'
        title_label.text = 'Tracks'
        layout.add_widget(title_label)

        @list = QListWidget.new(widget)
        list.object_name = 'results_list'
        layout.add_widget(list, 1)
      end

      def render_items(state)
        list.block_signals(true)
        list.clear
        state.search_results.each { |track| list.add_item(track.display_label) }
        list.add_item(loader_item_text) if state.tracks_loading_more
        list.current_row = state.selected_index if state.selected_index
        list.block_signals(false)
      end

      def scrolled_near_bottom?
        scrollbar = list.verticalScrollBar
        return false unless scrollbar
        return false unless scrollbar.maximum.positive?

        scrollbar.value >= scrollbar.maximum - SCROLL_LOAD_THRESHOLD
      end

      def signature(state)
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
    end
  end
end
