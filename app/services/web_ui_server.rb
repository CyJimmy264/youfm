# frozen_string_literal: true

require 'json'
require 'puma'
require 'puma/server'
require 'rack'
require 'securerandom'

module YouFM
  module Services
    class WebUiServer
      DEFAULT_PORT = 8264
      ACTION_LABELS = {
        toggle: 'Play/Pause',
        next: 'Next',
        generate: 'Generate Next',
        apply_numeric_settings: 'Apply Settings',
        apply_recommendation_strategies: 'Apply Strategies',
        use_device: 'Use Device',
        select_playlist: 'Use Playlist',
        refresh: 'Refresh',
        sync_library: 'Sync Library'
      }.freeze

      def initialize(view_model:, settings_store:, port: DEFAULT_PORT)
        @view_model = view_model
        @settings_store = settings_store
        @port = port
        @mutex = Mutex.new
        @action_queue = Queue.new
        @server = nil
        @thread = nil
        @worker_thread = nil
      end

      def start
        return if @server

        @server = Puma::Server.new(
          self,
          nil,
          min_threads: 0,
          max_threads: 16,
          persistent_timeout: 0,
          enable_keep_alives: false,
          log_writer: Puma::LogWriter.null
        )
        @server.add_tcp_listener('127.0.0.1', port)
        start_action_worker
        @thread = @server.run
        Services::Logger.info("[youfm] web ui listening on http://127.0.0.1:#{port}")
      end

      def stop
        return unless @server

        @server.stop(true)
        @thread&.join(2)
      ensure
        stop_action_worker
        @server = nil
        @thread = nil
      end

      private

      attr_reader :view_model, :settings_store, :port, :mutex, :server, :action_queue

      public

      def call(env)
        request = Rack::Request.new(env)
        case request.path_info
        when '/'
          handle_index
        when '/action'
          handle_action(request)
        when '/log'
          handle_log
        when '/log/stream'
          handle_log_stream
        when '/state'
          handle_state
        when '/state/stream'
          handle_state_stream
        else
          not_found
        end
      end

      private

      def handle_index
        started_at = Time.now
        response = render_response
        log_request_timing('GET /', started_at)
        response
      end

      def handle_action(request)
        return method_not_allowed unless request.post?

        params = request.params
        message = dispatch_action(params['name'].to_s, params.dup)
        return render_action_response(message) if json_action_request?(request)

        redirect_home
      rescue StandardError => e
        message = "Web UI action failed: #{e.message}"
        mutex.synchronize { view_model.status = message }
        return render_action_response(message, status: 500) if json_action_request?(request)

        redirect_home
      end

      def handle_log
        started_at = monotonic_time
        request_id = SecureRandom.hex(3)
        payload = recent_log_payload
        tail_elapsed_ms = elapsed_ms_since(started_at)
        json_response(JSON.generate(payload), { 'Cache-Control' => 'no-store' })
      ensure
        if started_at
          log_slow_log_request(request_id:, tail_elapsed_ms:, total_elapsed_ms: elapsed_ms_since(started_at))
        end
      end

      def handle_log_stream
        [
          200,
          {
            'Content-Type' => 'text/event-stream; charset=utf-8',
            'Cache-Control' => 'no-store',
            'Connection' => 'keep-alive',
            'X-Accel-Buffering' => 'no'
          },
          log_stream_body
        ]
      end

      def handle_state
        json_response(JSON.generate(state_payload), { 'Cache-Control' => 'no-store' })
      end

      def handle_state_stream
        [
          200,
          {
            'Content-Type' => 'text/event-stream; charset=utf-8',
            'Cache-Control' => 'no-store',
            'Connection' => 'keep-alive',
            'X-Accel-Buffering' => 'no'
          },
          state_stream_body
        ]
      end

      def dispatch_action(name, params)
        action = normalize_action_name(name)
        start_action_worker
        pending_count = action_queue.size + 1
        message = "Web UI action queued: #{action_label(action)}"
        message = "#{message} (pending: #{pending_count})" if pending_count > 1
        mutex.synchronize { view_model.status = message }
        Services::Logger.info(
          "[youfm] web ui action queued: #{action_label(action)} pending=#{pending_count} " \
          "worker_alive=#{@worker_thread&.alive?}"
        )
        action_queue << [action, params]

        message
      end

      def start_action_worker
        return if @worker_thread&.alive?

        @worker_thread = Thread.new do
          loop do
            action = action_queue.pop
            break if action == :stop

            run_queued_action(*action)
          rescue StandardError => e
            mutex.synchronize { view_model.status = "Web UI action failed: #{e.message}" }
          end
        end
      end

      def stop_action_worker
        return unless @worker_thread

        action_queue << :stop
        @worker_thread.join(2)
      ensure
        @worker_thread = nil
      end

      def run_queued_action(name, params)
        label = action_label(name)
        mutex.synchronize { view_model.status = "Web UI action started: #{label}" }
        Services::Logger.info("[youfm] web ui action started: #{label}")
        run_action(name, params)
        Services::Logger.info("[youfm] web ui action finished: #{label}")
      end

      def run_action(name, params)
        send("#{normalize_action_name(name)}_action", params)
      rescue NoMethodError
        unknown_action
      end

      def action_label(name)
        ACTION_LABELS.fetch(name, 'Unknown')
      end

      def render_response
        started_at = Time.now
        body = render_page
        log_request_timing('render_page', started_at)
        html_response(body)
      end

      def method_not_allowed
        rack_response(405, 'Method Not Allowed', 'Allow' => 'POST')
      end

      def render_action_response(message, status: 202)
        json_response(JSON.generate(status: message), {}, status:)
      end

      def json_action_request?(request)
        request.get_header('HTTP_ACCEPT').to_s.include?('application/json')
      end

      def redirect_home
        rack_response(303, '', 'Location' => '/')
      end

      def not_found
        rack_response(404, 'Not Found')
      end

      def html_response(body)
        rack_response(200, body, 'Content-Type' => 'text/html; charset=utf-8')
      end

      def json_response(body, headers = {}, status: 200)
        rack_response(status, body, { 'Content-Type' => 'application/json; charset=utf-8' }.merge(headers))
      end

      def rack_response(status, body, headers = {})
        headers = { 'Content-Length' => body.bytesize.to_s }.merge(headers)
        [status, headers, [body]]
      end

      def render_page
        render_payload = build_render_payload
        log_render_step('html') { renderer.render(**render_payload) }
      end

      def renderer
        @renderer ||= WebUi::Renderer.new
      end

      def build_render_payload
        {
          state: log_render_step('state') { view_model.state },
          pool_limit: log_render_step('similar_artist_pool_limit') { view_model.similar_artist_pool_limit },
          minimum_queue_size: log_render_step('minimum_recommended_queue_size') do
            view_model.minimum_recommended_queue_size
          end,
          maximum_queue_size: log_render_step('maximum_recommended_queue_size') do
            view_model.maximum_recommended_queue_size
          end,
          seed_source_labels: log_render_step('recommendation_seed_source_labels') do
            view_model.recommendation_seed_source_labels
          end,
          enabled_seed_sources: log_render_step('enabled_recommendation_seed_source_names') do
            view_model.enabled_recommendation_seed_source_names
          end,
          generator_labels: log_render_step('recommendation_generator_labels') do
            view_model.recommendation_generator_labels
          end,
          enabled_generators: log_render_step('enabled_recommendation_generator_names') do
            view_model.enabled_recommendation_generator_names
          end,
          generator_weights: log_render_step('recommendation_generator_weights') do
            view_model.recommendation_generator_weights
          end,
          exclude_explicit: log_render_step('exclude_explicit_recommendations') do
            view_model.filter_explicit_content?
          end,
          replay_seed_before_recommendation: log_render_step('replay_seed_before_recommendation') do
            view_model.replay_seed_before_recommendation?
          end,
          seed_replay_interval: log_render_step('seed_replay_interval') { view_model.seed_replay_interval }
        }
      end

      def log_request_timing(label, started_at)
        elapsed_ms = ((Time.now - started_at) * 1000).round
        Services::Logger.info("[youfm] web ui #{label} finished in #{elapsed_ms}ms")
      rescue StandardError
        nil
      end

      def log_render_step(label)
        started_at = monotonic_time
        yield
      ensure
        elapsed_ms = ((monotonic_time - started_at) * 1000).round
        Services::Logger.info("[youfm] web ui render_step #{label} finished in #{elapsed_ms}ms") if elapsed_ms >= 100
      end

      def log_elapsed(label, started_at)
        Services::Logger.info("[youfm] web ui #{label} finished in #{elapsed_ms_since(started_at)}ms")
      rescue StandardError
        nil
      end

      def recent_log_payload
        lines = Services::LogFile.tail(lines: 50).reject { |line| line.to_s.empty? }
        lines = ['No log lines yet'] if lines.empty?
        { path: Services::LogFile.path, lines: lines, revision: Services::LogFile.revision }
      end

      def log_stream_body
        Enumerator.new do |stream|
          payload = recent_log_payload
          stream << sse_event('log', payload)
          revision = payload.fetch(:revision)

          loop do
            next_revision = Services::LogFile.wait_for_revision(revision, timeout: 15)
            if next_revision > revision
              payload = recent_log_payload
              stream << sse_event('log', payload)
              revision = payload.fetch(:revision)
            else
              stream << ": heartbeat\n\n"
            end
          end
        rescue IOError, Errno::EPIPE
          nil
        end
      end

      def state_payload
        state = view_model.state
        {
          now_playing: state.now_playing,
          recommendation_seed: state.recommendation_seed,
          status_message: state.status_message,
          device_name: state.device_name.to_s.empty? ? 'no active device' : state.device_name,
          playlists: playlist_payload(state),
          selected_playlist_index: state.selected_playlist_index,
          tracks_title: state.tracks_title,
          seed_track_count: Array(state.search_results).length,
          revision: view_model.revision
        }
      end

      def playlist_payload(state)
        Array(state.playlists).each_with_index.map do |playlist, index|
          { index: index, label: playlist.display_label }
        end
      end

      def state_stream_body
        Enumerator.new do |stream|
          payload = state_payload
          stream << sse_event('state', payload)
          revision = payload.fetch(:revision)

          loop do
            next_revision = view_model.wait_for_revision(revision, timeout: 15)
            if next_revision > revision
              payload = state_payload
              stream << sse_event('state', payload)
              revision = payload.fetch(:revision)
            else
              stream << ": heartbeat\n\n"
            end
          end
        rescue IOError, Errno::EPIPE
          nil
        end
      end

      def sse_event(event, payload)
        "event: #{event}\ndata: #{JSON.generate(payload)}\n\n"
      end

      def log_slow_log_request(request_id:, tail_elapsed_ms:, total_elapsed_ms:)
        return if total_elapsed_ms < 100

        Services::Logger.info(
          "[youfm] web ui GET /log #{request_id} tail=#{tail_elapsed_ms || 0}ms total=#{total_elapsed_ms}ms"
        )
      rescue StandardError
        nil
      end

      def toggle_action(_params)
        view_model.toggle_playback
      end

      def next_action(_params)
        view_model.skip_to_next
      end

      def generate_action(_params)
        view_model.generate_recommendation_async
      end

      def apply_numeric_settings_action(params)
        applied_limit = view_model.update_similar_artist_pool_limit(params['pool_limit'].to_s)
        settings_store.write_similar_artist_pool_limit(applied_limit) if applied_limit
        applied_queue_size = view_model.update_minimum_recommended_queue_size(params['minimum_queue_size'].to_s)
        settings_store.write_minimum_recommended_queue_size(applied_queue_size) if applied_queue_size
        applied_maximum_queue_size = view_model.update_maximum_recommended_queue_size(params['maximum_queue_size'].to_s)
        settings_store.write_maximum_recommended_queue_size(applied_maximum_queue_size) if applied_maximum_queue_size
      end

      def apply_recommendation_strategies_action(params)
        applied_settings = view_model.update_recommendation_pipeline_settings(
          seed_sources: params.fetch('seed_source_names', []),
          generators: params.fetch('generator_names', []),
          generator_weights: params.fetch('generator_weights', {})
        )
        settings_store.write_enabled_seed_source_names(applied_settings.fetch(:seed_sources))
        settings_store.write_enabled_generator_names(applied_settings.fetch(:generators))
        settings_store.write_generator_weights(applied_settings.fetch(:generator_weights))
        exclude_explicit = view_model.filter_explicit_content = (params['exclude_explicit'] == '1')
        settings_store.write_exclude_explicit_recommendations(exclude_explicit)
        replay_settings = view_model.update_seed_replay_settings(
          enabled: params['replay_seed_before_recommendation'] == '1',
          interval: params['seed_replay_interval'].to_s
        )
        return unless replay_settings.is_a?(Hash)

        settings_store.write_replay_seed_before_recommendation(replay_settings.fetch(:enabled))
        settings_store.write_seed_replay_interval(replay_settings.fetch(:interval))
      end

      def use_device_action(params)
        view_model.select_device_index(params['device_index'].to_i)
        view_model.activate_selected_device
      end

      def select_playlist_action(params)
        view_model.select_playlist_index(params['playlist_index'].to_i)
      end

      def refresh_action(_params)
        view_model.refresh_playback
      end

      def sync_library_action(_params)
        view_model.refresh_library
      end

      def unknown_action
        view_model.status = 'Unknown Web UI action'
      end

      def normalize_action_name(name)
        name.to_s.tr('-', '_').to_sym
      end

      def elapsed_ms_since(started_at)
        ((monotonic_time - started_at) * 1000).round
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
