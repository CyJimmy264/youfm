# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

module YouFM
  module Services
    class RecommendedQueueStore
      def initialize(path: default_path)
        @path = path
      end

      def load
        payload = load_payload
        return empty_payload unless payload.is_a?(Hash)

        {
          track_ids: Array(payload['track_ids']).map(&:to_s).reject(&:empty?),
          tracks: Array(payload['tracks']).filter_map { |track| normalize_track_payload(track) },
          seeds: normalize_seeds(payload['seeds'])
        }
      end

      def save(track_ids:, tracks:, seeds:)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(
          path,
          YAML.dump(
            'saved_at' => Time.now.utc.iso8601,
            'track_ids' => Array(track_ids).map(&:to_s).reject(&:empty?),
            'tracks' => Array(tracks).map { |track| serialize_track(track) },
            'seeds' => normalize_seeds(seeds)
          )
        )
      end

      def clear
        FileUtils.rm_f(path)
      rescue StandardError
        nil
      end

      private

      attr_reader :path

      def load_payload
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      rescue StandardError
        {}
      end

      def empty_payload
        { track_ids: [], tracks: [], seeds: {} }
      end

      def normalize_track_payload(track)
        return nil unless track.is_a?(Hash)

        {
          'id' => track['id'].to_s,
          'name' => track['name'].to_s,
          'artists' => Array(track['artists']).filter_map { |artist| normalize_artist_payload(artist) },
          'album' => { 'name' => track.dig('album', 'name').to_s },
          'uri' => track['uri'].to_s,
          'duration_ms' => track['duration_ms'].to_i
        }.then { |payload| payload['id'].empty? ? nil : payload }
      end

      def normalize_artist_payload(artist)
        return { 'name' => artist.to_s } unless artist.is_a?(Hash)

        name = artist['name'].to_s
        { 'name' => name } unless name.empty?
      end

      def normalize_seeds(seeds)
        return {} unless seeds.is_a?(Hash)

        seeds.each_with_object({}) do |(track_id, seed_label), result|
          normalized_track_id = track_id.to_s
          next if normalized_track_id.empty?

          result[normalized_track_id] = seed_label.to_s
        end
      end

      def serialize_track(track)
        {
          'id' => track.id.to_s,
          'name' => track.title.to_s,
          'artists' => track.artists.map { |artist| { 'name' => artist.to_s } },
          'album' => { 'name' => track.album.to_s },
          'uri' => track.uri.to_s,
          'duration_ms' => track.duration_ms.to_i
        }
      end

      def default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'youfm', 'recommended_queue.yml')
      end
    end
  end
end
