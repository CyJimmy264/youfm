# frozen_string_literal: true

require 'cgi'
require 'json'
require 'webrick'

module YouFM
  module Services
    class WebUiServer
      DEFAULT_PORT = 8264

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

        @server = WEBrick::HTTPServer.new(
          BindAddress: '127.0.0.1',
          Port: port,
          AccessLog: [],
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        )
        mount_routes
        start_action_worker
        @thread = Thread.new { @server.start }
        puts "[youfm] web ui listening on http://127.0.0.1:#{port}"
      end

      def stop
        return unless @server

        @server.shutdown
        @thread&.join(2)
      ensure
        stop_action_worker
        @server = nil
        @thread = nil
      end

      private

      attr_reader :view_model, :settings_store, :port, :mutex, :server, :action_queue

      def mount_routes
        server.mount_proc('/') { |request, response| handle_index(request, response) }
        server.mount_proc('/action') { |request, response| handle_action(request, response) }
      end

      def handle_index(_request, response)
        started_at = Time.now
        render_response(response)
        log_request_timing('GET /', started_at)
      end

      def handle_action(request, response)
        return method_not_allowed(response) unless request.request_method == 'POST'

        message = dispatch_action(request.query['name'].to_s, request.query.dup)
        return render_action_response(response, message) if json_action_request?(request)

        redirect_home(response)
      rescue StandardError => e
        message = "Web UI action failed: #{e.message}"
        mutex.synchronize { view_model.status = message }
        return render_action_response(response, message, status: 500) if json_action_request?(request)

        redirect_home(response)
      end

      def dispatch_action(name, params)
        start_action_worker
        pending_count = action_queue.size + 1
        message = "Web UI action queued: #{action_label(name)}"
        message = "#{message} (pending: #{pending_count})" if pending_count > 1
        mutex.synchronize { view_model.status = message }
        puts "[youfm] web ui action queued: #{action_label(name)} pending=#{pending_count} " \
             "worker_alive=#{@worker_thread&.alive?}"
        action_queue << [name, params]

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
        puts "[youfm] web ui action started: #{label}"
        run_action(name, params)
        puts "[youfm] web ui action finished: #{label}"
      end

      def run_action(name, params)
        case name
        when 'toggle'
          view_model.toggle_playback
        when 'next'
          view_model.skip_to_next
        when 'generate'
          view_model.generate_recommendation
        when 'apply_pool'
          applied_limit = view_model.update_similar_artist_pool_limit(params['pool_limit'].to_s)
          settings_store.write_similar_artist_pool_limit(applied_limit) if applied_limit
        when 'use_device'
          view_model.select_device_index(params['device_index'].to_i)
          view_model.activate_selected_device
        when 'refresh'
          view_model.refresh_playback
        when 'sync_library'
          view_model.refresh_library
        else
          view_model.status = 'Unknown Web UI action'
        end
      end

      def action_label(name)
        case name
        when 'toggle'
          'Play/Pause'
        when 'next'
          'Next'
        when 'generate'
          'Generate Next'
        when 'apply_pool'
          'Apply Artist Pool'
        when 'use_device'
          'Use Device'
        when 'refresh'
          'Refresh'
        when 'sync_library'
          'Sync Library'
        else
          'Unknown'
        end
      end

      def render_response(response)
        response.status = 200
        response['Content-Type'] = 'text/html; charset=utf-8'
        started_at = Time.now
        response.body = render_page
        response.content_length = response.body.bytesize
        response.keep_alive = false
        log_request_timing('render_page', started_at)
      end

      def method_not_allowed(response)
        response.status = 405
        response['Allow'] = 'POST'
        response.body = 'Method Not Allowed'
      end

      def render_action_response(response, message, status: 202)
        response.status = status
        response['Content-Type'] = 'application/json; charset=utf-8'
        response.body = JSON.generate(status: message)
        response.content_length = response.body.bytesize
        response.keep_alive = false
      end

      def json_action_request?(request)
        Array(request.header['accept']).any? { |value| value.include?('application/json') }
      end

      def redirect_home(response)
        response.status = 303
        response['Location'] = '/'
      end

      def render_page
        state = view_model.state
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
                padding: 24px;
                border: 1px solid var(--line);
                border-radius: 24px;
                background: color-mix(in srgb, var(--panel), transparent 8%);
                box-shadow: 0 24px 80px rgba(0, 0, 0, 0.28);
              }
              .status { display: grid; gap: 8px; margin-bottom: 22px; color: var(--muted); }
              .status strong { color: var(--text); font-weight: 650; }
              .actions { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
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
              select { min-width: min(360px, 100%); }
              form { margin: 0; }
              .pool, .device-form { display: flex; gap: 8px; align-items: center; }
              .pool label, .device-form label { color: var(--muted); }
              @media (max-width: 640px) {
                main { margin: 20px auto; }
                .panel { padding: 18px; border-radius: 18px; }
                .actions, .pool, .device-form { align-items: stretch; flex-direction: column; }
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
                  #{device_form(state)}
                  #{action_form('toggle', 'Play/Pause', primary: true)}
                  #{action_form('next', 'Next')}
                  #{action_form('generate', 'Generate Next')}
                  <form class="pool" method="post" action="/action">
                    <input type="hidden" name="name" value="apply_pool">
                    <label for="pool_limit">Artist Pool</label>
                    <input id="pool_limit" name="pool_limit" value="#{escape(view_model.similar_artist_pool_limit)}">
                    <button type="submit">Apply</button>
                  </form>
                  #{action_form('refresh', 'Refresh')}
                  #{action_form('sync_library', 'Sync Library')}
                </div>
              </section>
            </main>
            <script>
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
        puts("[youfm] web ui #{label} finished in #{elapsed_ms}ms")
      rescue StandardError
        nil
      end
    end
  end
end
