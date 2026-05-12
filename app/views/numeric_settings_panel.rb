# frozen_string_literal: true

module YouFM
  module Views
    class NumericSettingsPanel
      attr_reader :widget

      def initialize(parent:, view_model:, settings_store:)
        @widget = QWidget.new(parent)
        @view_model = view_model
        @settings_store = settings_store
        @inputs = {}
        @apply_handler = nil
        build_layout
      end

      def on_apply(&block)
        @apply_handler = block
      end

      def bind_return_pressed
        inputs.each_value do |input|
          input.connect('returnPressed()') { @apply_handler&.call }
        end
      end

      def load_saved_settings
        load_setting(
          name: :pool_limit,
          stored_value: settings_store.read_similar_artist_pool_limit,
          apply: ->(value) { view_model.update_similar_artist_pool_limit(value) },
          fallback: -> { view_model.similar_artist_pool_limit }
        )
        load_setting(
          name: :minimum_queue_size,
          stored_value: settings_store.read_minimum_recommended_queue_size,
          apply: ->(value) { view_model.update_minimum_recommended_queue_size(value) },
          fallback: -> { view_model.minimum_recommended_queue_size }
        )
        load_setting(
          name: :maximum_queue_size,
          stored_value: settings_store.read_maximum_recommended_queue_size,
          apply: ->(value) { view_model.update_maximum_recommended_queue_size(value) },
          fallback: -> { view_model.maximum_recommended_queue_size }
        )
      rescue StandardError => e
        Services::Logger.warn("[youfm] load numeric settings failed: #{e.class}: #{e.message}")
        apply_current_values
      end

      def apply_changes
        apply_setting(
          name: :pool_limit,
          apply: ->(value) { view_model.update_similar_artist_pool_limit(value) },
          fallback: -> { view_model.similar_artist_pool_limit },
          persist: ->(value) { settings_store.write_similar_artist_pool_limit(value) }
        )
        apply_setting(
          name: :minimum_queue_size,
          apply: ->(value) { view_model.update_minimum_recommended_queue_size(value) },
          fallback: -> { view_model.minimum_recommended_queue_size },
          persist: ->(value) { settings_store.write_minimum_recommended_queue_size(value) }
        )
        apply_setting(
          name: :maximum_queue_size,
          apply: ->(value) { view_model.update_maximum_recommended_queue_size(value) },
          fallback: -> { view_model.maximum_recommended_queue_size },
          persist: ->(value) { settings_store.write_maximum_recommended_queue_size(value) }
        )
      rescue StandardError => e
        Services::Logger.warn("[youfm] save numeric settings failed: #{e.class}: #{e.message}")
      end

      def apply_current_values
        input(:pool_limit).text = view_model.similar_artist_pool_limit.to_s
        input(:minimum_queue_size).text = view_model.minimum_recommended_queue_size.to_s
        input(:maximum_queue_size).text = view_model.maximum_recommended_queue_size.to_s
      end

      private

      attr_reader :view_model, :settings_store, :inputs

      def build_layout
        layout = QVBoxLayout.new(widget)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.spacing = 8
        layout.add_widget(label)
        layout.add_widget(inputs_widget)
      end

      def label
        QLabel.new(widget).tap do |panel_label|
          panel_label.object_name = 'status_label'
          panel_label.text = 'Numeric Settings'
        end
      end

      def inputs_widget
        QWidget.new(widget).tap do |container|
          layout = QVBoxLayout.new(container)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 8
          build_input(:pool_limit, container, placeholder: 'Pool limit', value: view_model.similar_artist_pool_limit)
          build_input(
            :minimum_queue_size,
            container,
            placeholder: 'Min queue',
            value: view_model.minimum_recommended_queue_size
          )
          build_input(
            :maximum_queue_size,
            container,
            placeholder: 'Max queue',
            value: view_model.maximum_recommended_queue_size
          )
          layout.add_widget(build_row(container, 'Artist Pool', input(:pool_limit)))
          layout.add_widget(build_row(container, 'Min Queue', input(:minimum_queue_size)))
          layout.add_widget(build_row(container, 'Max Queue', input(:maximum_queue_size)))
        end
      end

      def build_input(name, parent, placeholder:, value:)
        inputs[name] = QLineEdit.new(parent).tap do |input|
          input.object_name = 'search_input'
          input.placeholder_text = placeholder
          input.maximum_width = 96
          input.text = value.to_s
        end
      end

      def build_row(parent, label_text, field)
        QWidget.new(parent).tap do |row|
          layout = QHBoxLayout.new(row)
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 8
          layout.add_widget(QLabel.new(row).tap do |label|
            label.object_name = 'status_label'
            label.text = label_text
          end)
          layout.add_widget(field)
          layout.add_stretch(1)
        end
      end

      def input(name)
        inputs.fetch(name)
      end

      def load_setting(name:, stored_value:, apply:, fallback:)
        if stored_value.nil?
          input(name).text = fallback.call.to_s
        else
          applied_value = apply.call(stored_value.to_s)
          input(name).text = (applied_value || fallback.call).to_s
        end
      end

      def apply_setting(name:, apply:, fallback:, persist:)
        applied_value = apply.call(input(name).text.to_s)
        if applied_value
          input(name).text = applied_value.to_s
          persist.call(applied_value)
        else
          input(name).text = fallback.call.to_s
        end
      end
    end
  end
end
