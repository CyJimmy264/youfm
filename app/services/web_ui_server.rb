# frozen_string_literal: true

require 'cgi'
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
        @action_in_flight = false
        @server = nil
        @thread = nil
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
        @thread = Thread.new { @server.start }
        puts "[youfm] web ui listening on http://127.0.0.1:#{port}"
      end

      def stop
        return unless @server

        @server.shutdown
        @thread&.join(2)
      ensure
        @server = nil
        @thread = nil
      end

      private

      attr_reader :view_model, :settings_store, :port, :mutex, :server

      def mount_routes
        server.mount_proc('/') { |request, response| handle_index(request, response) }
        server.mount_proc('/action') { |request, response| handle_action(request, response) }
      end

      def handle_index(_request, response)
        render_response(response)
      end

      def handle_action(request, response)
        return method_not_allowed(response) unless request.request_method == 'POST'

        dispatch_action(request.query['name'].to_s, request.query.dup)
        redirect_home(response)
      rescue StandardError => e
        mutex.synchronize { view_model.state.status_message = "Web UI action failed: #{e.message}" }
        redirect_home(response)
      end

      def dispatch_action(name, params)
        mutex.synchronize do
          if @action_in_flight
            view_model.state.status_message = 'Web UI action skipped: another action is still running'
            return
          end

          @action_in_flight = true
          view_model.state.status_message = "Web UI action queued: #{action_label(name)}"
        end

        Thread.new do
          mutex.synchronize { run_action(name, params) }
        rescue StandardError => e
          mutex.synchronize { view_model.state.status_message = "Web UI action failed: #{e.message}" }
        ensure
          mutex.synchronize { @action_in_flight = false }
        end
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
        when 'refresh'
          view_model.refresh_playback
        when 'sync_library'
          view_model.refresh_library
        else
          view_model.state.status_message = 'Unknown Web UI action'
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
        response.body = render_page
      end

      def method_not_allowed(response)
        response.status = 405
        response['Allow'] = 'POST'
        response.body = 'Method Not Allowed'
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
              button, input {
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
              input {
                width: 120px;
                padding: 0 12px;
                color: var(--text);
                background: #0f151d;
              }
              form { margin: 0; }
              .pool { display: flex; gap: 8px; align-items: center; }
              .pool label { color: var(--muted); }
              @media (max-width: 640px) {
                main { margin: 20px auto; }
                .panel { padding: 18px; border-radius: 18px; }
                .actions, .pool { align-items: stretch; flex-direction: column; }
                button, input { width: 100%; }
              }
            </style>
          </head>
          <body>
            <main>
              <h1>YouFM</h1>
              <section class="panel">
                <div class="status">
                  <div><strong>Now:</strong> #{escape(state.now_playing)}</div>
                  <div><strong>Recommendation Seed:</strong> #{escape(state.recommendation_seed)}</div>
                  <div><strong>Status:</strong> #{escape(state.status_message)}</div>
                  <div><strong>Device:</strong> #{escape(state.device_name.to_s.empty? ? 'no active device' : state.device_name)}</div>
                </div>
                <div class="actions">
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
          </body>
          </html>
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
    end
  end
end
