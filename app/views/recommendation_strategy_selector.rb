# frozen_string_literal: true

module YouFM
  module Views
    class RecommendationStrategySelector
      attr_reader :widget

      def initialize(parent:, strategy_labels:, enabled_names:, exclude_explicit:)
        @widget = QWidget.new(parent)
        @strategy_labels = strategy_labels
        @checkboxes = {}
        @exclude_explicit_checkbox = nil
        @applying = false
        build_layout
        apply_state(enabled_names:, exclude_explicit:)
      end

      def on_change(&)
        @on_change = Proc.new(&)
      end

      def enabled_names
        checkboxes.filter_map do |name, checkbox|
          name if checkbox.is_checked
        end
      end

      def apply_state(enabled_names:, exclude_explicit:)
        @applying = true
        enabled = Array(enabled_names).map(&:to_sym)
        checkboxes.each do |name, checkbox|
          checkbox.checked = enabled.include?(name)
        end
        exclude_explicit_checkbox.checked = exclude_explicit == true
      ensure
        @applying = false
      end

      private

      attr_reader :strategy_labels, :checkboxes, :exclude_explicit_checkbox

      def build_layout
        layout = QVBoxLayout.new(widget)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.spacing = 8
        layout.add_widget(label)
        layout.add_widget(checkboxes_widget)
      end

      def checkboxes_widget
        QWidget.new(widget).tap do |container|
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          strategy_labels.each do |name, text|
            checkbox = build_checkbox(text)
            checkboxes[name] = checkbox
            layout.add_widget(checkbox)
          end
          @exclude_explicit_checkbox = build_checkbox('Exclude explicit content')
          layout.add_widget(exclude_explicit_checkbox)
        end
      end

      def label
        QLabel.new(widget).tap do |label|
          label.object_name = 'status_label'
          label.text = 'Strategies'
        end
      end

      def build_checkbox(text)
        QCheckBox.new(widget).tap do |checkbox|
          checkbox.object_name = 'strategy_checkbox'
          checkbox.text = text
          checkbox.focus_policy = Qt::NoFocus
          checkbox.connect('toggled(bool)') { emit_change }
        end
      end

      def emit_change
        return if @applying

        @on_change&.call(enabled_names, exclude_explicit_checkbox.is_checked)
      end
    end
  end
end
