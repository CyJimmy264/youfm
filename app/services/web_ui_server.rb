# frozen_string_literal: true

require 'cgi'
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
        apply_pool: 'Apply Artist Pool',
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
        state = log_render_step('state') { view_model.state }
        device_html = log_render_step('device_form') { device_form(state) }
        playlist_html = log_render_step('playlist_form') { playlist_form(state) }
        pool_limit = log_render_step('similar_artist_pool_limit') { view_model.similar_artist_pool_limit }

        log_render_step('html') do
          <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>YouFM Web UI</title>
              <style>
                :root {
                  --bg: #11151c;
                  --panel: #19212c;
                  --text: #edf2f7;
                  --muted: #9aa7b4;
                  --line: #2a3442;
                  --accent: #f0b35a;
                  --button: #243040;
                }
                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  min-height: 100vh;
                  font: 16px/1.45 "Iosevka Aile", "Aptos", sans-serif;
                  color: var(--text);
                  background:
                    radial-gradient(circle at top left, rgba(240, 179, 90, 0.18), transparent 34rem),
                    linear-gradient(135deg, #0e1218, var(--bg));
                }
                main { width: min(880px, calc(100vw - 32px)); margin: 40px auto; }
                h1 { margin: 0 0 20px; font-size: clamp(32px, 8vw, 64px); letter-spacing: -0.06em; }
                .panel {
                  margin-bottom: 18px;
                  padding: 24px;
                  border: 1px solid var(--line);
                  border-radius: 24px;
                  background: color-mix(in srgb, var(--panel), transparent 8%);
                  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.28);
                }
                .status { display: grid; gap: 8px; margin-bottom: 22px; color: var(--muted); }
                .status strong { color: var(--text); font-weight: 650; }
                .actions { display: grid; gap: 14px; }
                .button-row { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
                button, input, select {
                  min-height: 44px;
                  border: 1px solid var(--line);
                  border-radius: 14px;
                  font: inherit;
                }
                button {
                  padding: 0 18px;
                  color: var(--text);
                  background: var(--button);
                  cursor: pointer;
                }
                button.primary { color: #1a1205; background: var(--accent); border-color: var(--accent); }
                input, select {
                  padding: 0 12px;
                  color: var(--text);
                  background: #0f151d;
                }
                input { width: 120px; }
                select { min-width: 0; width: 100%; }
                form { margin: 0; }
                .pool { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
                .device-form,
                .playlist-form {
                  display: grid;
                  grid-template-columns: auto minmax(240px, 1fr) auto;
                  gap: 10px;
                  align-items: center;
                  width: 100%;
                }
                .pool label,
                .device-form label,
                .playlist-form label { color: var(--muted); }
                .form-summary {
                  grid-column: 2 / -1;
                  color: var(--muted);
                  font-size: 13px;
                }
                .log-header { display: flex; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
                .log-title { margin: 0; font-size: 18px; font-weight: 650; }
                .log-path { color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }
                .log-lines {
                  max-height: 420px;
                  margin: 0;
                  padding: 14px;
                  overflow: auto;
                  border: 1px solid var(--line);
                  border-radius: 14px;
                  color: #d7e2ec;
                  background: #0a0f15;
                  font: 13px/1.5 "Iosevka Term", "JetBrains Mono", monospace;
                  white-space: pre-wrap;
                }
                @media (max-width: 640px) {
                  main { margin: 20px auto; }
                  .panel { padding: 18px; border-radius: 18px; }
                  .button-row, .pool { align-items: stretch; flex-direction: column; }
                  .device-form { grid-template-columns: 1fr; }
                  .playlist-form { grid-template-columns: 1fr; }
                  .form-summary { grid-column: auto; }
                  .log-header { flex-direction: column; }
                  button, input, select { width: 100%; }
                }
              </style>
            </head>
            <body>
              <main>
                <h1>YouFM</h1>
                <section class="panel">
                  <div class="status">
                    <div><strong>Now:</strong> <span id="now_playing">#{escape(state.now_playing)}</span></div>
                    <div><strong>Recommendation Seed:</strong> <span id="recommendation_seed">#{escape(state.recommendation_seed)}</span></div>
                    <div><strong>Status:</strong> <span id="status_message">#{escape(state.status_message)}</span></div>
                    <div><strong>Device:</strong> <span id="device_name">#{escape(state.device_name.to_s.empty? ? 'no active device' : state.device_name)}</span></div>
                  </div>
                  <div class="actions">
                    #{device_html}
                    #{playlist_html}
                    <div class="button-row">
                      #{action_form('toggle', 'Play/Pause', primary: true)}
                      #{action_form('next', 'Next')}
                      #{action_form('generate', 'Generate Next')}
                      #{action_form('refresh', 'Refresh')}
                      #{action_form('sync_library', 'Sync Library')}
                    </div>
                    <form class="pool" method="post" action="/action">
                      <input type="hidden" name="name" value="apply_pool">
                      <label for="pool_limit">Artist Pool</label>
                      <input id="pool_limit" name="pool_limit" value="#{escape(pool_limit)}">
                      <button type="submit">Apply</button>
                    </form>
                  </div>
                </section>
                #{recent_log_panel}
              </main>
              <script>
                function renderLog(payload) {
                  const log = document.getElementById('recent_log');
                  const path = document.getElementById('log_path');
                  if (!log) return;

                  if (path && payload.path) path.textContent = payload.path;
                  log.textContent = (payload.lines || ['No log lines yet']).join('\\n');
                  log.scrollTop = log.scrollHeight;
                }

                function renderState(payload) {
                  const fields = {
                    now_playing: payload.now_playing,
                    recommendation_seed: payload.recommendation_seed,
                    status_message: payload.status_message,
                    device_name: payload.device_name
                  };

                  Object.entries(fields).forEach(([id, value]) => {
                    const element = document.getElementById(id);
                    if (element) element.textContent = value;
                  });

                  renderPlaylists(payload);
                }

                function renderPlaylists(payload) {
                  const select = document.getElementById('playlist_index');
                  const button = document.getElementById('use_playlist_button');
                  const summary = document.getElementById('seed_playlist_summary');
                  if (!select) return;

                  const playlists = payload.playlists || [];
                  const selectedIndex = String(payload.selected_playlist_index ?? 0);
                  const previousValue = select.value;
                  const userIsChoosing = document.activeElement === select;
                  const playlistSignature = JSON.stringify(
                    playlists.map((playlist) => [playlist.index, playlist.label])
                  );
                  if (select.dataset.playlistSignature !== playlistSignature) {
                    select.replaceChildren(
                      ...playlists.map((playlist) => {
                        const option = document.createElement('option');
                        option.value = playlist.index;
                        option.textContent = playlist.label;
                        return option;
                      })
                    );
                    select.dataset.playlistSignature = playlistSignature;
                  }
                  const availableValues = playlists.map((playlist) => String(playlist.index));
                  if (userIsChoosing && availableValues.includes(previousValue)) {
                    select.value = previousValue;
                  } else if (availableValues.includes(selectedIndex)) {
                    select.value = selectedIndex;
                  } else if (availableValues.includes(previousValue)) {
                    select.value = previousValue;
                  }
                  select.disabled = playlists.length === 0;
                  if (button) button.disabled = playlists.length === 0;
                  if (summary) {
                    summary.textContent = `${payload.tracks_title || 'Tracks'} · ${payload.seed_track_count || 0} seed tracks`;
                  }
                }

                async function refreshLog() {
                  try {
                    const response = await fetch('/log', { headers: { 'Accept': 'application/json' } });
                    renderLog(await response.json());
                  } catch (error) {
                    const log = document.getElementById('recent_log');
                    if (log.textContent === 'Loading log...') log.textContent = 'No log lines yet';
                  }
                }

                async function refreshState() {
                  try {
                    const response = await fetch('/state', { headers: { 'Accept': 'application/json' } });
                    renderState(await response.json());
                  } catch (error) {}
                }

                if (window.EventSource) {
                  const logEvents = new EventSource('/log/stream');
                  const stateEvents = new EventSource('/state/stream');
                  logEvents.addEventListener('log', (event) => renderLog(JSON.parse(event.data)));
                  stateEvents.addEventListener('state', (event) => renderState(JSON.parse(event.data)));
                  logEvents.onerror = () => {
                    if (document.getElementById('recent_log')?.textContent === 'Loading log...') refreshLog();
                  };
                  stateEvents.onerror = () => refreshState();
                  window.addEventListener('beforeunload', () => {
                    logEvents.close();
                    stateEvents.close();
                  });
                } else {
                  refreshLog();
                  refreshState();
                  setInterval(refreshLog, 1000);
                  setInterval(refreshState, 1000);
                }

                document.querySelectorAll('form[action="/action"]').forEach((form) => {
                  form.addEventListener('submit', async (event) => {
                    event.preventDefault();
                    const submitter = event.submitter;
                    if (submitter) submitter.disabled = true;

                    try {
                      const response = await fetch(form.action, {
                        method: 'POST',
                        headers: { 'Accept': 'application/json' },
                        body: new FormData(form)
                      });
                      const payload = await response.json();
                      const status = document.getElementById('status_message');
                      if (status && payload.status) status.textContent = payload.status;
                    } catch (error) {
                      const status = document.getElementById('status_message');
                      if (status) status.textContent = `Web UI request failed: ${error.message}`;
                    } finally {
                      if (submitter) submitter.disabled = false;
                    }
                  });
                });

              </script>
            </body>
            </html>
          HTML
        end
      end

      def recent_log_panel
        <<~HTML
          <section class="panel">
            <div class="log-header">
              <h2 class="log-title">Recent Log</h2>
              <div id="log_path" class="log-path">#{escape(Services::LogFile.path)}</div>
            </div>
            <pre id="recent_log" class="log-lines">Loading log...</pre>
          </section>
        HTML
      end

      def device_form(state)
        devices = Array(state.devices)
        selected_index = state.selected_device_index || devices.index(&:active) || 0
        options = devices.each_with_index.map do |device, index|
          selected = index == selected_index ? ' selected' : ''
          label = "#{device.name} · #{device.type}"
          label += ' · active' if device.active
          %(<option value="#{index}"#{selected}>#{escape(label)}</option>)
        end.join
        disabled = devices.empty? ? ' disabled' : ''

        <<~HTML
          <form class="device-form" method="post" action="/action">
            <input type="hidden" name="name" value="use_device">
            <label for="device_index">Device</label>
            <select id="device_index" name="device_index"#{disabled}>#{options}</select>
            <button type="submit"#{disabled}>Use Device</button>
          </form>
        HTML
      end

      def playlist_form(state)
        playlists = Array(state.playlists)
        selected_index = state.selected_playlist_index || 0
        options = playlists.each_with_index.map do |playlist, index|
          selected = index == selected_index ? ' selected' : ''
          %(<option value="#{index}"#{selected}>#{escape(playlist.display_label)}</option>)
        end.join
        disabled = playlists.empty? ? ' disabled' : ''
        summary = "#{state.tracks_title || 'Tracks'} · #{Array(state.search_results).length} seed tracks"

        <<~HTML
          <form class="playlist-form" method="post" action="/action">
            <input type="hidden" name="name" value="select_playlist">
            <label for="playlist_index">Seed Playlist</label>
            <select id="playlist_index" name="playlist_index"#{disabled}>#{options}</select>
            <button id="use_playlist_button" type="submit"#{disabled}>Use Playlist</button>
            <div id="seed_playlist_summary" class="form-summary">#{escape(summary)}</div>
          </form>
        HTML
      end

      def action_form(name, label, primary: false)
        button_class = primary ? ' class="primary"' : ''
        <<~HTML
          <form method="post" action="/action">
            <input type="hidden" name="name" value="#{escape(name)}">
            <button#{button_class} type="submit">#{escape(label)}</button>
          </form>
        HTML
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
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

      def apply_pool_action(params)
        applied_limit = view_model.update_similar_artist_pool_limit(params['pool_limit'].to_s)
        settings_store.write_similar_artist_pool_limit(applied_limit) if applied_limit
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
