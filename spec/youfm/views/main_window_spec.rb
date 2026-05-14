# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Views::MainWindow do
  describe '#enqueue_external_state_render' do
    it 'syncs settings widgets when state revision changes' do
      state = instance_double(YouFM::ViewModels::MainViewModel::State)
      view_model = instance_double(
        YouFM::ViewModels::MainViewModel,
        revision: 2,
        state: state,
        enabled_recommendation_strategy_names: [:track_similar],
        filter_explicit_content?: false,
        replay_seed_before_recommendation?: true,
        seed_replay_interval: 5
      )
      tracks_panel = instance_double(YouFM::Views::TracksPanel, rendered_current?: true)
      numeric_settings_panel = instance_double(YouFM::Views::NumericSettingsPanel, apply_current_values: nil)
      strategy_selector = instance_double(YouFM::Views::RecommendationStrategySelector, apply_state: nil)
      window = described_class.allocate
      window.instance_variable_set(:@view_model, view_model)
      window.instance_variable_set(:@tracks_panel, tracks_panel)
      window.instance_variable_set(:@numeric_settings_panel, numeric_settings_panel)
      window.instance_variable_set(:@recommendation_strategy_selector, strategy_selector)
      window.instance_variable_set(:@render_queue, Queue.new)
      window.instance_variable_set(:@last_seen_state_revision, 1)
      allow(window).to receive(:render_status)

      window.send(:enqueue_external_state_render)

      expect(numeric_settings_panel).to have_received(:apply_current_values)
      expect(strategy_selector).to have_received(:apply_state).with(
        enabled_names: [:track_similar],
        exclude_explicit: false,
        replay_seed_before_recommendation: true,
        seed_replay_interval: 5
      )
      expect(window).to have_received(:render_status)
    end
  end

  describe '#playback_inactive?' do
    it 'treats paused playback as inactive for cold polling' do
      state = instance_double(
        YouFM::ViewModels::MainViewModel::State,
        playing: false,
        now_playing: 'Paused: Track - Artist'
      )
      view_model = instance_double(YouFM::ViewModels::MainViewModel, state: state)
      window = described_class.allocate
      window.instance_variable_set(:@view_model, view_model)

      expect(window.send(:playback_inactive?)).to be(true)
    end
  end
end
