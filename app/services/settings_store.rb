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
