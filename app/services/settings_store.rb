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

      def read_enabled_recommendation_strategy_names
        payload.fetch('enabled_recommendation_strategy_names', nil)
      end

      def write_enabled_recommendation_strategy_names(names)
        write_payload(payload.merge('enabled_recommendation_strategy_names' => Array(names).map(&:to_s)))
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
