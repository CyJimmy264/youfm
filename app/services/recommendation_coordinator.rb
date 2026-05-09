# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationCoordinator
      def initialize(recommendation_generator:, source:, seed_store:)
        @recommendation_generator = recommendation_generator
        @source = source
        @seed_store = seed_store
        @in_flight = false
      end

      def similar_artist_pool_limit
        recommendation_generator.similar_artist_pool_limit
      end

      def similar_artist_pool_limit=(value)
        recommendation_generator.similar_artist_pool_limit = value
      end

      def reset
        @in_flight = false
      end

      def enqueue(seed_tracks:, excluded_track_ids:, playlist_name:, queue_tracks:, trigger:, append_track:,
                  update_status:)
        return recommendation_status(trigger, :missing_seed_tracks, update_status:) if seed_tracks.empty?

        recommendation = recommendation_generator.generate_with_seed(
          seed_tracks,
          excluded_track_ids: excluded_track_ids,
          playlist_name: playlist_name
        )
        recommended_track = recommendation&.track
        return recommendation_status(trigger, :not_found, update_status:) unless recommended_track

        seed_label = seed_label_for(recommendation.seed_track, playlist_name)
        return recommendation_status(trigger, :duplicate, update_status:) if queue_tracks.any? do |track|
          track.id == recommended_track.id
        end

        source.add_to_queue(recommended_track)
        seed_store.save(recommended_track.id, seed_label, label: recommended_track.display_label)
        append_track.call(recommended_track, seed_label)
        message = "Added recommendation to Spotify queue: #{recommended_track.display_label}"
        update_status.call(message)
        message
      end

      def enqueue_async(**kwargs)
        if @in_flight
          Services::Logger.info(
            "[youfm] recommendation skipped: trigger=#{kwargs.fetch(:trigger)} reason=already_in_flight"
          )
          return
        end

        @in_flight = true
        Thread.new do
          enqueue(**kwargs)
        rescue StandardError => e
          message = "Recommendation failed: #{e.message}"
          kwargs.fetch(:update_status).call(message)
          Services::Logger.warn("[youfm] recommendation failed: #{e.class}: #{e.message}")
        ensure
          @in_flight = false
        end
      end

      private

      attr_reader :recommendation_generator, :source, :seed_store

      def seed_label_for(track, playlist_name)
        label = "#{track.title} — #{track.artist_line}"
        playlist = playlist_name.to_s
        return label if playlist.empty?

        "#{label} (Взят из плейлиста: #{playlist})"
      end

      def recommendation_status(trigger, reason, update_status:)
        prefix = trigger == :playback_change ? 'Auto-recommendation skipped' : 'Recommendation skipped'

        details =
          case reason
          when :missing_seed_tracks
            'no seed tracks are loaded'
          when :not_found
            'Last.fm/Spotify did not return a suitable track'
          when :duplicate
            'the candidate is already in the queue'
          else
            'unknown reason'
          end

        message = "#{prefix}: #{details}"
        update_status.call(message)
        message
      end
    end
  end
end
