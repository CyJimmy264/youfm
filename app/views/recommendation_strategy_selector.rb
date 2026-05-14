# frozen_string_literal: true

module YouFM
  module Views
    class RecommendationStrategySelector
      attr_reader :widget

      def initialize(parent:, seed_source_labels:, enabled_seed_source_names:, generator_labels:,
                     enabled_generator_names:, generator_weights:, exclude_explicit:,
                     replay_seed_before_recommendation:, seed_replay_interval:)
        @widget = QWidget.new(parent)
        @seed_source_labels = seed_source_labels
        @generator_labels = generator_labels
        @seed_source_checkboxes = {}
        @generator_checkboxes = {}
        @generator_weight_inputs = {}
        @exclude_explicit_checkbox = nil
        @replay_seed_checkbox = nil
        @seed_replay_interval_input = nil
        @applying = false
        build_layout
        apply_state(
          enabled_seed_source_names:,
          enabled_generator_names:,
          generator_weights:,
          exclude_explicit:,
          replay_seed_before_recommendation:,
          seed_replay_interval:
        )
      end

      def on_change(&)
        @on_change = Proc.new(&)
      end

      def apply_state(enabled_seed_source_names:, enabled_generator_names:, generator_weights:, exclude_explicit:,
                      replay_seed_before_recommendation:, seed_replay_interval:)
        @applying = true
        enabled_sources = Array(enabled_seed_source_names).map(&:to_sym)
        enabled_generators = Array(enabled_generator_names).map(&:to_sym)
        seed_source_checkboxes.each do |name, checkbox|
          checkbox.checked = enabled_sources.include?(name)
        end
        generator_checkboxes.each do |name, checkbox|
          checkbox.checked = enabled_generators.include?(name)
        end
        generator_weight_inputs.each do |name, input|
          input.text = generator_weights.fetch(name, generator_weights.fetch(name.to_s, 1)).to_s
        end
        exclude_explicit_checkbox.checked = exclude_explicit == true
        replay_seed_checkbox.checked = replay_seed_before_recommendation == true
        seed_replay_interval_input.text = seed_replay_interval.to_s
      ensure
        @applying = false
      end

      private

      attr_reader :seed_source_labels, :generator_labels, :seed_source_checkboxes, :generator_checkboxes,
                  :generator_weight_inputs, :exclude_explicit_checkbox, :replay_seed_checkbox,
                  :seed_replay_interval_input

      def build_layout
        layout = QVBoxLayout.new(widget)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.spacing = 8
        layout.add_widget(build_section('Seed sources', build_seed_source_options))
        layout.add_widget(build_section('Generators', build_generator_options))
        layout.add_widget(build_section('Queue modifiers', build_queue_modifier_options))
      end

      def build_section(title, body)
        QGroupBox.new(widget).tap do |container|
          container.title = title
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(8, 10, 8, 8)
          layout.spacing = 6
          layout.add_widget(body)
        end
      end

      def build_seed_source_options
        QWidget.new(widget).tap do |container|
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          seed_source_labels.each do |name, text|
            checkbox = build_checkbox(text)
            seed_source_checkboxes[name] = checkbox
            layout.add_widget(checkbox)
          end
        end
      end

      def build_generator_options
        QWidget.new(widget).tap do |container|
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          generator_labels.each do |name, text|
            layout.add_widget(build_generator_row(name, text))
          end
          @exclude_explicit_checkbox = build_checkbox('Exclude explicit content')
          layout.add_widget(exclude_explicit_checkbox)
        end
      end

      def build_queue_modifier_options
        QWidget.new(widget).tap do |container|
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 6
          layout.add_widget(seed_replay_row)
        end
      end

      def build_generator_row(name, text)
        QWidget.new(widget).tap do |container|
          layout = QHBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 8
          checkbox = build_checkbox(text)
          generator_checkboxes[name] = checkbox
          layout.add_widget(checkbox)
          input = QLineEdit.new(container)
          input.object_name = 'search_input'
          input.placeholder_text = 'Weight'
          input.maximum_width = 84
          input.connect('returnPressed()') { emit_change }
          generator_weight_inputs[name] = input
          layout.add_widget(input)
          layout.add_stretch(1)
        end
      end

      def seed_replay_row
        QWidget.new(widget).tap do |container|
          layout = QHBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 8
          @replay_seed_checkbox = build_checkbox('Replay seed every N generated tracks')
          layout.add_widget(replay_seed_checkbox)
          @seed_replay_interval_input = QLineEdit.new(container)
          seed_replay_interval_input.object_name = 'search_input'
          seed_replay_interval_input.placeholder_text = 'Every N'
          seed_replay_interval_input.maximum_width = 84
          seed_replay_interval_input.connect('returnPressed()') { emit_change }
          layout.add_widget(seed_replay_interval_input)
          layout.add_widget(QLabel.new(container).tap do |label|
            label.object_name = 'status_label'
            label.text = 'Ignored for Raw seed'
          end)
          layout.add_stretch(1)
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

        @on_change&.call(
          seed_sources: enabled_seed_source_names,
          generators: enabled_generator_names,
          weights: generator_weights,
          exclude_explicit: exclude_explicit_checkbox.is_checked,
          replay_seed: replay_seed_checkbox.is_checked,
          interval: seed_replay_interval_input.text.to_s
        )
      end

      def enabled_seed_source_names
        seed_source_checkboxes.filter_map { |name, checkbox| name if checkbox.is_checked }
      end

      def enabled_generator_names
        generator_checkboxes.filter_map { |name, checkbox| name if checkbox.is_checked }
      end

      def generator_weights
        generator_weight_inputs.transform_values { |input| input.text.to_s }
      end
    end
  end
end
