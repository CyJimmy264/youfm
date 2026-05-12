# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

module YouFM
  module Services
    class RecommendationSeedStore
      DEFAULT_TTL = 24 * 60 * 60

      def initialize(path: default_path, ttl: DEFAULT_TTL, clock: -> { Time.now })
        @path = path
        @ttl = ttl
        @clock = clock
        @store = nil
      end

      def fetch(track_id)
        normalized_track_id = track_id.to_s
        entry = load_store[normalized_track_id]
        return nil unless entry.is_a?(Hash)

        if expired?(entry)
          delete(normalized_track_id)
          return nil
        end

        seed_label = entry['seed_label'].to_s
        delete(normalized_track_id)
        seed_label
      end

      def save(track_id, seed_label, label: nil)
        normalized_track_id = track_id.to_s
        normalized_seed_label = seed_label.to_s
        return if normalized_track_id.empty? || normalized_seed_label.empty?

        store = prune_expired(load_store)
        store[normalized_track_id] = {
          'label' => label.to_s,
          'seed_label' => normalized_seed_label,
          'saved_at' => clock.call.utc.iso8601
        }
        persist_store(store)
      end

      def existing_for(track_ids)
        normalized_track_ids = Array(track_ids).map(&:to_s).reject(&:empty?)
        return {} if normalized_track_ids.empty?

        store = prune_expired(load_store)
        persist_store(store) if store != @store

        normalized_track_ids.each_with_object({}) do |track_id, result|
          entry = store[track_id]
          next unless entry.is_a?(Hash)

          seed_label = entry['seed_label'].to_s
          next if seed_label.empty?

          result[track_id] = seed_label
        end
      end

      private

      attr_reader :path, :ttl, :clock

      def expired?(entry)
        saved_at = Time.iso8601(entry['saved_at'].to_s)
        saved_at < clock.call - ttl
      rescue ArgumentError, TypeError
        true
      end

      def prune_expired(store)
        store.reject { |_track_id, entry| !entry.is_a?(Hash) || expired?(entry) }
      end

      def load_store
        return @store if @store
        return @store = {} unless File.exist?(path)

        loaded_store = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
        @store = loaded_store.is_a?(Hash) ? loaded_store : {}
      rescue StandardError
        @store = {}
      end

      def persist_store(store)
        @store = store
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(store))
      end

      def delete(track_id)
        store = load_store
        store.delete(track_id)
        persist_store(store)
      end

      def default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'youfm', 'recommendation_seeds.yml')
      end
    end
  end
end
