# frozen_string_literal: true

module YouFM
  module Views
    class RecommendationFiltersPanel
      attr_reader :widget

      def initialize(parent:, view_model:, settings_store:)
        @widget = QWidget.new(parent)
        @view_model = view_model
        @settings_store = settings_store
        @title_blacklist_input = nil
        @apply_handler = nil
        build_layout
      end

      def on_apply(&block)
        @apply_handler = block
      end

      def load_saved_settings
        stored_lines = settings_store.read_recommendation_title_blacklist
        if stored_lines.nil?
          apply_current_values
        else
          applied_lines = view_model.update_recommendation_title_blacklist(stored_lines)
          assign_title_blacklist_lines(applied_lines)
        end
      rescue StandardError => e
        Services::Logger.warn("[youfm] load recommendation filters failed: #{e.class}: #{e.message}")
        apply_current_values
      end

      def apply_changes
        applied_lines = view_model.update_recommendation_title_blacklist(title_blacklist_lines)
        settings_store.write_recommendation_title_blacklist(applied_lines)
        assign_title_blacklist_lines(applied_lines)
      rescue StandardError => e
        Services::Logger.warn("[youfm] save recommendation filters failed: #{e.class}: #{e.message}")
      end

      def apply_current_values
        assign_title_blacklist_lines(view_model.recommendation_title_blacklist)
      end

      private

      attr_reader :view_model, :settings_store, :title_blacklist_input

      def build_layout
        layout = QVBoxLayout.new(widget)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.spacing = 0
        layout.add_widget(group_box)
      end

      def group_box
        QGroupBox.new(widget).tap do |container|
          container.title = 'Filters'
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(8, 10, 8, 8)
          layout.spacing = 8
          layout.add_widget(helper_text(container))
          @title_blacklist_input = QTextEdit.new(container)
          title_blacklist_input.object_name = 'search_input'
          title_blacklist_input.minimum_height = 180
          layout.add_widget(title_blacklist_input)
          layout.add_widget(apply_button(container))
        end
      end

      def helper_text(parent)
        QLabel.new(parent).tap do |label|
          label.object_name = 'status_label'
          label.text = 'Track title blacklist: one word or phrase per line'
          label.word_wrap = true
        end
      end

      def apply_button(parent)
        QPushButton.new(parent).tap do |button|
          button.text = 'Apply Filters'
          button.connect('clicked()') { @apply_handler&.call }
        end
      end

      def title_blacklist_lines
        title_blacklist_input.toPlainText.to_s.lines.map(&:strip).reject(&:empty?).uniq
      end

      def assign_title_blacklist_lines(lines)
        title_blacklist_input.setPlainText(Array(lines).join("\n"))
      end
    end
  end
end
