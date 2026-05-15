# frozen_string_literal: true

module YouFM
  module Services
    class SettingsStore
      def initialize(path: default_path)
        @path = path
      end

      def read_theme_name
        payload.fetch('theme_name', nil)
      end

      def write_theme_name(theme_name)
        write_payload(payload.merge('theme_name' => theme_name))
      end

      def read_similar_artist_pool_limit
        payload.fetch('similar_artist_pool_limit', nil)
      end

      def write_similar_artist_pool_limit(limit)
        write_payload(payload.merge('similar_artist_pool_limit' => limit.to_i))
      end

      def read_minimum_recommended_queue_size
        payload.fetch('minimum_recommended_queue_size', nil)
      end

      def write_minimum_recommended_queue_size(size)
        write_payload(payload.merge('minimum_recommended_queue_size' => size.to_i))
      end

      def read_maximum_recommended_queue_size
        payload.fetch('maximum_recommended_queue_size', nil)
      end

      def write_maximum_recommended_queue_size(size)
        write_payload(payload.merge('maximum_recommended_queue_size' => size.to_i))
      end

      def read_enabled_recommendation_strategy_names
        payload.fetch('enabled_recommendation_strategy_names', nil)
      end

      def write_enabled_recommendation_strategy_names(names)
        write_payload(payload.merge('enabled_recommendation_strategy_names' => Array(names).map(&:to_s)))
      end

      def read_enabled_seed_source_names
        payload.fetch('enabled_seed_source_names', nil)
      end

      def write_enabled_seed_source_names(names)
        write_payload(payload.merge('enabled_seed_source_names' => Array(names).map(&:to_s)))
      end

      def read_seed_source_weights
        payload.fetch('seed_source_weights', nil)
      end

      def write_seed_source_weights(weights)
        normalized = weights.to_h.transform_keys(&:to_s).transform_values(&:to_i)
        write_payload(payload.merge('seed_source_weights' => normalized))
      end

      def read_enabled_generator_names
        payload.fetch('enabled_generator_names', nil)
      end

      def write_enabled_generator_names(names)
        write_payload(payload.merge('enabled_generator_names' => Array(names).map(&:to_s)))
      end

      def read_generator_weights
        payload.fetch('generator_weights', nil)
      end

      def write_generator_weights(weights)
        normalized = weights.to_h.transform_keys(&:to_s).transform_values(&:to_i)
        write_payload(payload.merge('generator_weights' => normalized))
      end

      def read_exclude_explicit_recommendations
        payload.fetch('exclude_explicit_recommendations', nil)
      end

      def write_exclude_explicit_recommendations(value)
        write_payload(payload.merge('exclude_explicit_recommendations' => value == true))
      end

      def read_replay_seed_before_recommendation
        payload.fetch('replay_seed_before_recommendation', nil)
      end

      def write_replay_seed_before_recommendation(value)
        write_payload(payload.merge('replay_seed_before_recommendation' => value == true))
      end

      def read_seed_replay_interval
        payload.fetch('seed_replay_interval', nil)
      end

      def write_seed_replay_interval(value)
        write_payload(payload.merge('seed_replay_interval' => value.to_i))
      end

      private

      attr_reader :path

      def payload
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        {}
      end

      def write_payload(data)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(data))
      end

      def default_path
        root = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
        File.join(root, 'youfm', 'config.yml')
      end
    end
  end
end
