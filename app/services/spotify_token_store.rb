# frozen_string_literal: true

module YouFM
  module Services
    class SpotifyTokenStore
      def initialize(path: default_path)
        @path = path
      end

      def load
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        {}
      end

      def save(payload)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(normalize_payload(payload)))
      end

      def clear
        FileUtils.rm_f(path)
      end

      private

      attr_reader :path

      def normalize_payload(payload)
        payload.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
      end

      def default_path
        root = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
        File.join(root, 'youfm', 'spotify_tokens.yml')
      end
    end
  end
end
