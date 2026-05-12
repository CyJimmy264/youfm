# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationCoordinator
      MAX_RECOMMENDATION_ATTEMPTS = 5
      MAX_TRANSIENT_RETRIES = 3
      TRANSIENT_RETRY_BASE_DELAY_SECONDS = 5

      Outcome = Struct.new(:status, :message, :track, :seed_label, keyword_init: true) do
        def self.success(track:, seed_label:)
          new(
            status: :success,
            message: "Added recommendation to Spotify queue: #{track.display_label}",
            track: track,
            seed_label: seed_label
          )
        end

        def self.not_added(trigger:, reason:)
          new(status: reason, message: not_added_message(trigger, reason))
        end

        def success?
          status == :success
        end

        def retryable?
          %i[not_found duplicate].include?(status)
        end

        def self.not_added_message(trigger, reason)
          prefix = trigger == :playback_change ? 'Auto-recommendation not added' : 'Recommendation not added'
          "#{prefix}: #{not_added_details(reason)}"
        end

        def self.not_added_details(reason)
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
        end

        private_class_method :not_added_message, :not_added_details
      end

      def initialize(recommendation_generator:, source:, seed_store:)
        @recommendation_generator = recommendation_generator
        @source = source
        @seed_store = seed_store
        @jobs = []
        @generation = 0
        @worker = nil
        @worker_starting = false
        @worker_mutex = Mutex.new
        @perform_mutex = Mutex.new
      end

      def similar_artist_pool_limit
        recommendation_generator.similar_artist_pool_limit
      end

      def similar_artist_pool_limit=(value)
        recommendation_generator.similar_artist_pool_limit = value
      end

      def enabled_strategy_names
        recommendation_generator.enabled_strategy_names
      end

      def enabled_strategy_names=(names)
        recommendation_generator.enabled_strategy_names = names
      end

      def exclude_explicit?
        recommendation_generator.exclude_explicit?
      end

      def exclude_explicit=(value)
        recommendation_generator.exclude_explicit = value
      end

      def reset
        worker_mutex.synchronize do
          jobs.clear
          @generation += 1
        end
      end

      def enqueue(**kwargs)
        perform_mutex.synchronize { perform_enqueue(**kwargs) }
      end

      def enqueue_async(**kwargs)
        pending_count, start_needed = enqueue_job(kwargs)
        Services::Logger.info(
          "[youfm] recommendation queued: trigger=#{kwargs.fetch(:trigger)} pending=#{pending_count}"
        )
        start_worker if start_needed
      end

      private

      attr_reader :recommendation_generator, :source, :seed_store, :jobs, :worker, :worker_mutex, :perform_mutex

      def enqueue_job(kwargs)
        worker_mutex.synchronize do
          jobs << kwargs.merge(generation: @generation)
          start_needed = !@worker_starting && !worker_alive?
          @worker_starting = true if start_needed
          [jobs.length, start_needed]
        end
      end

      def start_worker
        new_worker = Thread.new { process_jobs }
        worker_mutex.synchronize do
          @worker = new_worker
          @worker_starting = false
        end
      end

      def process_jobs
        loop do
          job = next_job
          break unless job

          perform_queued_enqueue(job)
        end
      end

      def next_job
        worker_mutex.synchronize do
          jobs.shift.tap do |job|
            @worker = nil unless job
          end
        end
      end

      def perform_queued_enqueue(job)
        generation = job.delete(:generation)
        job.delete(:transient_attempt)
        return if stale_generation?(generation)

        perform_mutex.synchronize do
          next if stale_generation?(generation)

          perform_enqueue(**job, stale: -> { stale_generation?(generation) })
        end
      rescue StandardError => e
        handle_queued_error(job, generation, e)
      end

      def stale_generation?(generation)
        worker_mutex.synchronize { @generation != generation }
      end

      def worker_alive?
        worker.respond_to?(:alive?) && worker.alive?
      end

      def perform_enqueue(seed_tracks:, excluded_track_ids:, playlist_name:, trigger:, append_track:, update_status:,
                          recommendation_attempt: 1, stale: -> { false })
        outcome = build_outcome(
          seed_tracks: seed_tracks,
          excluded_track_ids: excluded_track_ids,
          playlist_name: playlist_name,
          trigger: trigger
        )
        return if stale.call

        if retry_outcome?(outcome, recommendation_attempt)
          Services::Logger.info(
            "[youfm] recommendation retrying: trigger=#{trigger} reason=#{outcome.status} " \
            "attempt=#{recommendation_attempt + 1}/#{MAX_RECOMMENDATION_ATTEMPTS}"
          )
          return perform_enqueue(
            seed_tracks: seed_tracks,
            excluded_track_ids: excluded_track_ids,
            playlist_name: playlist_name,
            trigger: trigger,
            append_track: append_track,
            update_status: update_status,
            recommendation_attempt: recommendation_attempt + 1,
            stale: stale
          )
        end

        apply_outcome(outcome, append_track) if outcome.success?
        publish_outcome(outcome, update_status)
      end

      def build_outcome(seed_tracks:, excluded_track_ids:, playlist_name:, trigger:)
        return Outcome.not_added(trigger: trigger, reason: :missing_seed_tracks) if seed_tracks.empty?

        blocked_track_ids = resolved_track_ids(excluded_track_ids)
        recommendation = recommendation_generator.generate_with_seed(
          seed_tracks,
          excluded_track_ids: blocked_track_ids,
          playlist_name: playlist_name
        )
        recommended_track = recommendation&.track
        return Outcome.not_added(trigger: trigger, reason: :not_found) unless recommended_track

        seed_label = seed_label_for(recommendation.seed_track, playlist_name)
        if blocked_track_ids.include?(recommended_track.id)
          return Outcome.not_added(trigger: trigger, reason: :duplicate)
        end

        Outcome.success(track: recommended_track, seed_label: seed_label)
      end

      def retry_outcome?(outcome, recommendation_attempt)
        outcome.retryable? && recommendation_attempt < MAX_RECOMMENDATION_ATTEMPTS
      end

      def apply_outcome(outcome, append_track)
        source.add_to_queue(outcome.track)
        seed_store.save(outcome.track.id, outcome.seed_label, label: outcome.track.display_label)
        append_track.call(outcome.track, outcome.seed_label)
      end

      def publish_outcome(outcome, update_status)
        update_status.call(outcome.message)
        outcome.message
      end

      def handle_queued_error(job, generation, error)
        if retry_transient_error?(job, error)
          retry_queued_job(job, generation, error)
        else
          publish_error(job, error)
        end
      end

      def retry_transient_error?(job, error)
        transient_error?(error) && job.fetch(:transient_attempt, 0) < MAX_TRANSIENT_RETRIES
      end

      def retry_queued_job(job, generation, error)
        attempt = job.fetch(:transient_attempt, 0) + 1
        delay = transient_retry_delay(error, attempt)
        job.fetch(:update_status).call("Recommendation failed: #{error.message}; retrying in #{delay}s")
        Services::Logger.warn(
          "[youfm] recommendation transient failure: #{error.class}: #{error.message}; " \
          "retry=#{attempt}/#{MAX_TRANSIENT_RETRIES} delay=#{delay}s"
        )
        sleep(delay)
        requeue_job(job.merge(transient_attempt: attempt), generation) unless stale_generation?(generation)
      end

      def requeue_job(job, generation)
        worker_mutex.synchronize do
          jobs << job.merge(generation: generation)
        end
      end

      def publish_error(job, error)
        message = "Recommendation failed: #{error.message}"
        job.fetch(:update_status).call(message)
        Services::Logger.warn("[youfm] recommendation failed: #{error.class}: #{error.message}")
      end

      def transient_retry_delay(error, attempt)
        return error.retry_after_seconds if error.is_a?(SpotifyClient::RateLimitedError) &&
                                            error.retry_after_seconds&.positive?

        TRANSIENT_RETRY_BASE_DELAY_SECONDS * (2**(attempt - 1))
      end

      def transient_error?(error)
        return false if terminal_spotify_error?(error)

        error.is_a?(SpotifyClient::Error) || error.is_a?(LastfmClient::Error)
      end

      def terminal_spotify_error?(error)
        error.is_a?(SpotifyClient::AuthenticationError) ||
          error.is_a?(SpotifyClient::PlaybackUnavailableError) ||
          error.is_a?(SpotifyClient::DeviceUnavailableError)
      end

      def resolved_track_ids(track_ids)
        values = track_ids.respond_to?(:call) ? track_ids.call : track_ids
        Array(values).map(&:to_s)
      end

      def seed_label_for(track, playlist_name)
        label = "#{track.title} — #{track.artist_line}"
        playlist = playlist_name.to_s
        return label if playlist.empty?

        "#{label} (Взят из плейлиста: #{playlist})"
      end
    end
  end
end
