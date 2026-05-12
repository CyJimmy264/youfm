# frozen_string_literal: true

require 'erb'
require 'cgi'

module YouFM
  module WebUi
    class Renderer
      TEMPLATE_DIR = File.expand_path('templates', __dir__)

      def render(state:, pool_limit:, minimum_queue_size:, strategy_labels:, enabled_strategies:, exclude_explicit:)
        TemplateContext.new(
          state: state,
          pool_limit: pool_limit,
          minimum_queue_size: minimum_queue_size,
          strategy_labels: strategy_labels,
          enabled_strategies: enabled_strategies,
          exclude_explicit: exclude_explicit,
          stylesheet: stylesheet,
          javascript: javascript
        ).render(template)
      end

      private

      def template
        @template ||= ERB.new(File.read(File.join(TEMPLATE_DIR, 'index.html.erb')), trim_mode: '-')
      end

      def stylesheet
        @stylesheet ||= File.read(File.join(TEMPLATE_DIR, 'styles.css'))
      end

      def javascript
        @javascript ||= File.read(File.join(TEMPLATE_DIR, 'app.js'))
      end

      class TemplateContext
        def initialize(state:, pool_limit:, minimum_queue_size:, strategy_labels:, enabled_strategies:,
                       exclude_explicit:, stylesheet:, javascript:)
          @state = state
          @pool_limit = pool_limit
          @minimum_queue_size = minimum_queue_size
          @strategy_labels = strategy_labels
          @enabled_strategies = enabled_strategies
          @exclude_explicit = exclude_explicit
          @stylesheet = stylesheet
          @javascript = javascript
        end

        attr_reader :state, :pool_limit, :minimum_queue_size, :strategy_labels, :enabled_strategies,
                    :exclude_explicit, :stylesheet, :javascript

        def render(template)
          template.result(binding)
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

        def device_form
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

        def playlist_form
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

        def recommendation_strategies_form
          checkboxes = strategy_labels.map do |name, label|
            checked = enabled_strategies.include?(name) ? ' checked' : ''
            <<~HTML
              <label class="checkbox-label">
                <input type="checkbox" name="strategy_names[]" value="#{escape(name)}"#{checked}>
                <span>#{escape(label)}</span>
              </label>
            HTML
          end.join
          explicit_checked = exclude_explicit ? ' checked' : ''

          <<~HTML
            <form class="strategies-form" method="post" action="/action">
              <input type="hidden" name="name" value="apply_recommendation_strategies">
              <div class="strategies-heading">Recommendation Strategies</div>
              <div class="strategy-options">
                #{checkboxes}
                <label class="checkbox-label">
                  <input type="checkbox" name="exclude_explicit" value="1"#{explicit_checked}>
                  <span>Exclude explicit content</span>
                </label>
              </div>
              <button type="submit">Apply</button>
            </form>
          HTML
        end

        def escape(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
