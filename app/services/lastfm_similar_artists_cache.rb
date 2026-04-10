# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

module YouFM
  module Services
    class LastfmSimilarArtistsCache
      def initialize(path: default_path, clock: -> { Time.now })
        @path = path
        @clock = clock
      end

      def fetch(artist_name, ttl:)
        entry = load_store[cache_key(artist_name)]
        return nil unless entry.is_a?(Hash)

        fetched_at = Time.iso8601(entry['fetched_at'].to_s)
        return nil if fetched_at < clock.call - ttl

        Array(entry['artists'])
      rescue ArgumentError, TypeError
        nil
      end

      def save(artist_name, artists)
        store = load_store
        store[cache_key(artist_name)] = {
          'fetched_at' => clock.call.utc.iso8601,
          'artists' => artists.map { |artist| normalize_artist(artist) }
        }
        persist_store(store)
      end

      private

      attr_reader :path, :clock

      def cache_key(artist_name)
        artist_name.to_s.strip.downcase
      end

      def normalize_artist(artist)
        artist.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
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
        File.join(root, 'youfm', 'lastfm_similar_artists.yml')
      end
    end
  end
end
