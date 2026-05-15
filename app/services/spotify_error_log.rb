# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module YouFM
  module Services
    class SpotifyErrorLog
      class << self
        def append(event)
          new.append(event)
        end

        def default_path
          root = ENV.fetch('XDG_STATE_HOME', File.join(Dir.home, '.local', 'state'))
          File.join(root, 'youfm', 'spotify_errors.jsonl')
        end
      end

      def initialize(path: self.class.default_path, clock: -> { Time.now })
        @path = path
        @clock = clock
      end

      def append(event)
        entry = normalized_entry(event)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'ab') do |file|
          file.write("#{JSON.generate(entry)}\n")
        end
      rescue StandardError
        nil
      end

      private

      attr_reader :path, :clock

      def normalized_entry(event)
        {
          timestamp: clock.call.iso8601,
          event: event.fetch(:event).to_s,
          context: event.fetch(:context).to_s,
          payload: sanitize_payload(event.fetch(:payload, {}))
        }
      end

      def sanitize_payload(payload)
        case payload
        when Hash
          payload.transform_values { |value| sanitize_payload(value) }
        when Array
          payload.map { |value| sanitize_payload(value) }
        else
          payload
        end
      end
    end
  end
end
