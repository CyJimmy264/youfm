# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

module YouFM
  module Services
    class RecommendationHistoryStore
      DEFAULT_TTL = 24 * 60 * 60

      def initialize(path: default_path, ttl: DEFAULT_TTL, clock: -> { Time.now })
        @path = path
        @ttl = ttl
        @clock = clock
      end

      def load
        prune_expired(load_payload).keys
      end

      def remember(track_id)
        normalized_track_id = track_id.to_s
        return if normalized_track_id.empty?

        store = prune_expired(load_payload)
        store[normalized_track_id] = clock.call.utc.iso8601
        persist(store)
      end

      private

      attr_reader :path, :ttl, :clock

      def prune_expired(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(track_id, saved_at), result|
          normalized_track_id = track_id.to_s
          next if normalized_track_id.empty?
          next if expired?(saved_at)

          result[normalized_track_id] = saved_at.to_s
        end
      end

      def expired?(saved_at)
        Time.iso8601(saved_at.to_s) < clock.call - ttl
      rescue ArgumentError, TypeError
        true
      end

      def persist(payload)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(payload))
      end

      def load_payload
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        {}
      end

      def default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'youfm', 'recommendation_history.yml')
      end
    end
  end
end
