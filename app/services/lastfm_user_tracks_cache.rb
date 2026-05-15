# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

module YouFM
  module Services
    class LastfmUserTracksCache
      def initialize(path: default_path, clock: -> { Time.now })
        @path = path
        @clock = clock
      end

      def fetch(method_name, username, ttl:)
        entry = load_store[cache_key(method_name, username)]
        return nil unless entry.is_a?(Hash)

        fetched_at = Time.iso8601(entry['fetched_at'].to_s)
        return nil if fetched_at < clock.call - ttl

        {
          total_pages: entry['total_pages'].to_i,
          total_tracks: entry['total_tracks'].to_i
        }
      rescue ArgumentError, TypeError
        nil
      end

      def save(method_name, username, total_pages:, total_tracks:)
        store = load_store
        store[cache_key(method_name, username)] = {
          'fetched_at' => clock.call.utc.iso8601,
          'total_pages' => total_pages.to_i,
          'total_tracks' => total_tracks.to_i
        }
        persist_store(store)
      end

      private

      attr_reader :path, :clock

      def cache_key(method_name, username)
        [method_name.to_s.strip.downcase, username.to_s.strip.downcase].join('|')
      end

      def load_store
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        {}
      end

      def persist_store(store)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(store))
      end

      def default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'youfm', 'lastfm_user_tracks.yml')
      end
    end
  end
end
