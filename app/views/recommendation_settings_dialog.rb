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
      end

      def sync_from_view_model
        numeric_settings_panel.apply_current_values
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

      attr_reader :view_model, :settings_store, :strategy_selector, :numeric_settings_panel

      def build_dialog
        dialog.window_title = 'Recommendation Settings'
        dialog.modal = false
        dialog.resize(560, 520)
        layout = QVBoxLayout.new(dialog)
        layout.set_contents_margins(16, 16, 16, 16)
        layout.spacing = 12

        @numeric_settings_panel = NumericSettingsPanel.new(
          parent: dialog,
          view_model: view_model,
          settings_store: settings_store
        )
        numeric_settings_panel.on_apply { apply_numeric_settings }
        numeric_settings_panel.bind_return_pressed
        layout.add_widget(numeric_settings_panel.widget)

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
        layout.add_widget(strategy_selector.widget)
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
    end
  end
end
