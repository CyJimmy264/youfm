# frozen_string_literal: true

module YouFM
  module Views
    class RecommendationSettingsDialog
      attr_reader :dialog

      def initialize(parent:, view_model:, settings_store:)
        @view_model = view_model
        @settings_store = settings_store
        @dialog = QDialog.new(parent)
        build_dialog
      end

      def show
        sync_from_view_model
        dialog.show
        dialog.raise
        dialog.activate_window
      end

      def load_saved_settings
        numeric_settings_panel.load_saved_settings
        filters_panel.load_saved_settings
      end

      def sync_from_view_model
        numeric_settings_panel.apply_current_values
        filters_panel.apply_current_values
        strategy_selector.apply_state(
          enabled_seed_source_names: view_model.enabled_recommendation_seed_source_names,
          seed_source_weights: view_model.recommendation_seed_source_weights,
          enabled_generator_names: view_model.enabled_recommendation_generator_names,
          generator_weights: view_model.recommendation_generator_weights,
          exclude_explicit: view_model.filter_explicit_content?,
          replay_seed_before_recommendation: view_model.replay_seed_before_recommendation?,
          seed_replay_interval: view_model.seed_replay_interval
        )
      end

      private

      attr_reader :view_model, :settings_store, :strategy_selector, :numeric_settings_panel, :filters_panel

      def build_dialog
        dialog.window_title = 'Recommendation Settings'
        dialog.modal = false
        dialog.resize(900, 560)
        layout = QHBoxLayout.new(dialog)
        layout.set_contents_margins(16, 16, 16, 16)
        layout.spacing = 12

        layout.add_widget(build_left_column, 3)
        layout.add_widget(build_right_column, 2)
      end

      def build_left_column
        QWidget.new(dialog).tap do |column|
          layout = build_column_layout(column)
          build_numeric_settings_panel
          build_strategy_selector
          layout.add_widget(numeric_settings_panel.widget)
          layout.add_widget(strategy_selector.widget)
          layout.add_stretch(1)
        end
      end

      def build_right_column
        QWidget.new(dialog).tap do |column|
          layout = build_column_layout(column)
          build_filters_panel
          layout.add_widget(filters_panel.widget)
          layout.add_stretch(1)
        end
      end

      def build_column_layout(column)
        QVBoxLayout.new(column).tap do |layout|
          layout.set_contents_margins(0, 0, 0, 0)
          layout.spacing = 12
        end
      end

      def build_numeric_settings_panel
        @numeric_settings_panel = NumericSettingsPanel.new(
          parent: dialog,
          view_model: view_model,
          settings_store: settings_store
        )
        numeric_settings_panel.on_apply { apply_numeric_settings }
        numeric_settings_panel.bind_return_pressed
      end

      def build_strategy_selector
        @strategy_selector = RecommendationStrategySelector.new(
          parent: dialog,
          seed_source_labels: view_model.recommendation_seed_source_labels,
          enabled_seed_source_names: view_model.enabled_recommendation_seed_source_names,
          seed_source_weights: view_model.recommendation_seed_source_weights,
          generator_labels: view_model.recommendation_generator_labels,
          enabled_generator_names: view_model.enabled_recommendation_generator_names,
          generator_weights: view_model.recommendation_generator_weights,
          exclude_explicit: view_model.filter_explicit_content?,
          replay_seed_before_recommendation: view_model.replay_seed_before_recommendation?,
          seed_replay_interval: view_model.seed_replay_interval
        )
        strategy_selector.on_change { |settings| apply_settings(settings) }
      end

      def build_filters_panel
        @filters_panel = RecommendationFiltersPanel.new(
          parent: dialog,
          view_model: view_model,
          settings_store: settings_store
        )
        filters_panel.on_apply { apply_filters }
      end

      def apply_settings(settings)
        applied_settings = view_model.update_recommendation_pipeline_settings(
          seed_sources: settings.fetch(:seed_sources),
          seed_source_weights: settings.fetch(:seed_source_weights),
          generators: settings.fetch(:generators),
          generator_weights: settings.fetch(:weights)
        )
        settings_store.write_enabled_seed_source_names(applied_settings.fetch(:seed_sources))
        settings_store.write_seed_source_weights(applied_settings.fetch(:seed_source_weights))
        settings_store.write_enabled_generator_names(applied_settings.fetch(:generators))
        settings_store.write_generator_weights(applied_settings.fetch(:generator_weights))
        applied_exclude_explicit = view_model.filter_explicit_content = settings.fetch(:exclude_explicit)
        settings_store.write_exclude_explicit_recommendations(applied_exclude_explicit)
        replay_settings = view_model.update_seed_replay_settings(
          enabled: settings.fetch(:replay_seed),
          interval: settings.fetch(:interval)
        )
        if replay_settings.is_a?(Hash)
          settings_store.write_replay_seed_before_recommendation(replay_settings.fetch(:enabled))
          settings_store.write_seed_replay_interval(replay_settings.fetch(:interval))
        end
      rescue StandardError => e
        Services::Logger.warn("[youfm] save recommendation strategies failed: #{e.class}: #{e.message}")
      end

      def apply_numeric_settings
        numeric_settings_panel.apply_changes
      rescue StandardError => e
        Services::Logger.warn("[youfm] save numeric settings failed: #{e.class}: #{e.message}")
      end

      def apply_filters
        filters_panel.apply_changes
      rescue StandardError => e
        Services::Logger.warn("[youfm] save recommendation filters failed: #{e.class}: #{e.message}")
      end
    end
  end
end
