# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module YouFM
  module Services
    class SpotifyPlaylistCache
      def initialize(path: default_path)
        @path = path
        @store = nil
      end

      def fetch(playlist_id:, snapshot_id:, offset:, limit:)
        return nil if snapshot_id.to_s.empty?

        entry = load_store.dig(playlist_id.to_s, snapshot_id.to_s, cache_key(offset:, limit:))
        return nil unless entry.is_a?(Hash)

        {
          tracks: Array(entry['tracks']),
          has_more: entry['has_more'] == true
        }
      end

      def save(playlist_id:, snapshot_id:, offset:, limit:, tracks:, has_more:)
        return if snapshot_id.to_s.empty?

        store = load_store
        store[playlist_id.to_s] ||= {}
        store[playlist_id.to_s] = { snapshot_id.to_s => {} } unless store[playlist_id.to_s].key?(snapshot_id.to_s)
        store[playlist_id.to_s][snapshot_id.to_s][cache_key(offset:, limit:)] = {
          'tracks' => tracks,
          'has_more' => has_more
        }
        persist_store(store)
      end

      private

      attr_reader :path

      def cache_key(offset:, limit:)
        "#{offset}:#{limit}"
      end

      def load_store
        return @store if @store
        return @store = {} unless File.exist?(path)

        @store = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        @store = {}
      end

      def persist_store(store)
        @store = store
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(store))
      end

      def default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'youfm', 'spotify_playlist_pages.yml')
      end
    end
  end
end
