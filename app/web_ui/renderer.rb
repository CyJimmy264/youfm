# frozen_string_literal: true

require 'erb'
require 'cgi'

module YouFM
  module WebUi
    class Renderer
      TEMPLATE_DIR = File.expand_path('templates', __dir__)

      def render(state:, pool_limit:, minimum_queue_size:, maximum_queue_size:, seed_source_labels:,
                 enabled_seed_sources:, seed_source_weights:, generator_labels:, enabled_generators:,
                 generator_weights:, exclude_explicit:, title_blacklist:, replay_seed_before_recommendation:,
                 seed_replay_interval:)
        TemplateContext.new(
          state: state,
          pool_limit: pool_limit,
          minimum_queue_size: minimum_queue_size,
          maximum_queue_size: maximum_queue_size,
          seed_source_labels: seed_source_labels,
          enabled_seed_sources: enabled_seed_sources,
          seed_source_weights: seed_source_weights,
          generator_labels: generator_labels,
          enabled_generators: enabled_generators,
          generator_weights: generator_weights,
          exclude_explicit: exclude_explicit,
          title_blacklist: title_blacklist,
          replay_seed_before_recommendation: replay_seed_before_recommendation,
          seed_replay_interval: seed_replay_interval,
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
        def initialize(state:, pool_limit:, minimum_queue_size:, seed_source_labels:, enabled_seed_sources:,
                       seed_source_weights:,
                       generator_labels:, enabled_generators:, generator_weights:, maximum_queue_size:,
                       exclude_explicit:, title_blacklist:, replay_seed_before_recommendation:,
                       seed_replay_interval:, stylesheet:, javascript:)
          @state = state
          @pool_limit = pool_limit
          @minimum_queue_size = minimum_queue_size
          @maximum_queue_size = maximum_queue_size
          @seed_source_labels = seed_source_labels
          @enabled_seed_sources = enabled_seed_sources
          @seed_source_weights = seed_source_weights
          @generator_labels = generator_labels
          @enabled_generators = enabled_generators
          @generator_weights = generator_weights
          @exclude_explicit = exclude_explicit
          @title_blacklist = title_blacklist
          @replay_seed_before_recommendation = replay_seed_before_recommendation
          @seed_replay_interval = seed_replay_interval
          @stylesheet = stylesheet
          @javascript = javascript
        end

        attr_reader(
          :state, :pool_limit, :minimum_queue_size, :maximum_queue_size, :seed_source_labels, :enabled_seed_sources,
          :seed_source_weights,
          :generator_labels, :enabled_generators, :generator_weights,
          :exclude_explicit, :title_blacklist, :replay_seed_before_recommendation, :seed_replay_interval,
          :stylesheet, :javascript
        )

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
          seed_source_checkboxes = seed_source_labels.map do |name, label|
            checked = enabled_seed_sources.include?(name) ? ' checked' : ''
            weight = seed_source_weights.fetch(name, seed_source_weights.fetch(name.to_s, 1))
            <<~HTML
              <label class="checkbox-label checkbox-inline-setting">
                <input type="checkbox" name="seed_source_names[]" value="#{escape(name)}"#{checked}>
                <span>#{escape(label)}</span>
                <input name="seed_source_weights[#{escape(name)}]" value="#{escape(weight)}" class="inline-number">
              </label>
            HTML
          end.join
          generator_rows = generator_labels.map do |name, label|
            checked = enabled_generators.include?(name) ? ' checked' : ''
            weight = generator_weights.fetch(name, generator_weights.fetch(name.to_s, 1))
            <<~HTML
              <label class="checkbox-label checkbox-inline-setting">
                <input type="checkbox" name="generator_names[]" value="#{escape(name)}"#{checked}>
                <span>#{escape(label)}</span>
                <input name="generator_weights[#{escape(name)}]" value="#{escape(weight)}" class="inline-number">
              </label>
            HTML
          end.join
          explicit_checked = exclude_explicit ? ' checked' : ''
          replay_seed_checked = replay_seed_before_recommendation ? ' checked' : ''
          title_blacklist_value = Array(title_blacklist).join("\n")

          <<~HTML
            <form class="strategies-form" method="post" action="/action">
              <input type="hidden" name="name" value="apply_recommendation_strategies">
              <div class="strategies-heading">Seed Sources</div>
              <div class="strategy-options">
                #{seed_source_checkboxes}
              </div>
              <div class="strategies-heading">Generators</div>
              <div class="strategy-options">
                #{generator_rows}
                <label class="checkbox-label">
                  <input type="checkbox" name="exclude_explicit" value="1"#{explicit_checked}>
                  <span>Exclude explicit content</span>
                </label>
              </div>
              <div class="strategies-heading">Queue Modifiers</div>
              <div class="strategy-options">
                <label class="checkbox-label checkbox-inline-setting">
                  <input type="checkbox" name="replay_seed_before_recommendation" value="1"#{replay_seed_checked}>
                  <span>Replay seed every N generated tracks</span>
                  <input name="seed_replay_interval" value="#{escape(seed_replay_interval)}" class="inline-number">
                </label>
                <div class="form-summary">Ignored for Raw seed</div>
              </div>
              <div class="strategies-heading">Filters</div>
              <div class="strategy-options">
                <label class="checkbox-label">
                  <span>Track title blacklist</span>
                </label>
                <textarea name="recommendation_title_blacklist" class="settings-textarea">#{escape(title_blacklist_value)}</textarea>
                <div class="form-summary">One word or phrase per line</div>
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
