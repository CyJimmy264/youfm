# frozen_string_literal: true

module YouFM
  module ViewModels
    class RecommendedQueue
      RECENTLY_PLAYED_LIMIT = 5

      def initialize(state:, store: nil)
        @state = state
        @store = store
        @mutex = Mutex.new
        @track_ids = []
        @recently_played_track_ids = []
        restore
      end

      def blocked_track_ids
        mutex.synchronize { (track_ids + recently_played_track_ids).uniq }
      end

      def remember_playing_track(track_id)
        normalized_track_id = track_id.to_s
        return if normalized_track_id.empty?

        mutex.synchronize do
          recently_played_track_ids.unshift(normalized_track_id)
          recently_played_track_ids.uniq!
          recently_played_track_ids.slice!(RECENTLY_PLAYED_LIMIT..)
        end
      end

      def remember_now_playing_seed(track_id, now_playing_seeds)
        seed = state.queue_recommendation_seeds[track_id]
        now_playing_seeds[track_id] = seed if seed
      end

      def append(track, seed_label)
        mutex.synchronize do
          track_ids.unshift(track.id.to_s)
          track_ids.uniq!
          state.queue_recommendation_seeds = state.queue_recommendation_seeds.merge(track.id.to_s => seed_label.to_s)
          state.queue_tracks = filter_recently_played([track, *state.queue_tracks].uniq(&:id))
          normalize_selection!
          update_selected_seed!
          persist
          track_ids.length
        end
      end

      def remove(track_id)
        normalized_track_id = track_id.to_s
        return if normalized_track_id.empty?

        mutex.synchronize do
          track_ids.reject! { |queued_id| queued_id == normalized_track_id }
          state.queue_tracks = state.queue_tracks.reject { |track| track.id.to_s == normalized_track_id }
          state.queue_recommendation_seeds = state.queue_recommendation_seeds.reject do |queued_track_id, _seed|
            queued_track_id == normalized_track_id
          end
          normalize_selection!
          update_selected_seed!
          persist
        end
      end

      def sync(spotify_queue_tracks)
        mutex.synchronize do
          recommended_track_ids = track_ids.to_set
          state.queue_tracks = filter_recently_played(spotify_queue_tracks).select do |track|
            recommended_track_ids.include?(track.id.to_s)
          end
          @track_ids = state.queue_tracks.map { |track| track.id.to_s }
          retain_visible_seeds!
          normalize_selection!
          update_selected_seed!
          persist
        end
      end

      def clear
        mutex.synchronize do
          @track_ids = []
          @recently_played_track_ids = []
          store&.clear
        end
      end

      def update_selected_seed!
        track = selected_track
        seed = track && state.queue_recommendation_seeds[track.id.to_s]
        state.selected_queue_recommendation_seed = seed.to_s.empty? ? 'None' : seed
      end

      private

      attr_reader :state, :store, :mutex, :track_ids, :recently_played_track_ids

      def restore
        payload = store&.load
        return unless payload

        @track_ids = payload.fetch(:track_ids)
        state.queue_tracks = payload.fetch(:tracks).map { |track_payload| build_track(track_payload) }
        state.queue_recommendation_seeds = payload.fetch(:seeds)
        normalize_selection!
        update_selected_seed!
      rescue StandardError => e
        Services::Logger.warn("[youfm] restore recommended queue failed: #{e.class}: #{e.message}")
      end

      def persist
        store&.save(
          track_ids: track_ids,
          tracks: state.queue_tracks,
          seeds: state.queue_recommendation_seeds
        )
      rescue StandardError => e
        Services::Logger.warn("[youfm] persist recommended queue failed: #{e.class}: #{e.message}")
      end

      def filter_recently_played(tracks)
        tracks.reject { |track| recently_played_track_ids.include?(track.id.to_s) }
      end

      def retain_visible_seeds!
        visible_track_ids = state.queue_tracks.map { |track| track.id.to_s }
        state.queue_recommendation_seeds = state.queue_recommendation_seeds.slice(*visible_track_ids)
      end

      def normalize_selection!
        state.selected_queue_index =
          if state.queue_tracks.empty?
            nil
          elsif state.selected_queue_index.nil? || state.selected_queue_index >= state.queue_tracks.length
            0
          else
            state.selected_queue_index
          end
      end

      def selected_track
        return nil if state.selected_queue_index.nil?

        state.queue_tracks[state.selected_queue_index]
      end

      def build_track(track_payload)
        Models::Track.new(
          id: track_payload.fetch('id', ''),
          title: track_payload.fetch('name', 'Unknown Track'),
          artists: Array(track_payload['artists']).filter_map { |artist| artist['name'] },
          album: track_payload.dig('album', 'name').to_s,
          uri: track_payload.fetch('uri', ''),
          duration_ms: track_payload.fetch('duration_ms', 0)
        )
      end
    end
  end
end
