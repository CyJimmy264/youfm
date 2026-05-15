# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::SettingsStore do
  it 'persists and reloads numeric settings', :aggregate_failures do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'config.yml')
      store = described_class.new(path:)

      store.write_similar_artist_pool_limit(350)
      store.write_minimum_recommended_queue_size(3)
      store.write_maximum_recommended_queue_size(25)
      store.write_enabled_seed_source_names(%i[current_playlist recent_tracks])
      store.write_seed_source_weights(current_playlist: 4, recent_tracks: 2)
      store.write_enabled_generator_names(%i[raw_seed track_similar])
      store.write_generator_weights(raw_seed: 2, track_similar: 3)
      store.write_exclude_explicit_recommendations(true)
      store.write_replay_seed_before_recommendation(true)
      store.write_seed_replay_interval(4)

      reloaded_store = described_class.new(path:)
      expect(reloaded_store.read_similar_artist_pool_limit).to eq(350)
      expect(reloaded_store.read_minimum_recommended_queue_size).to eq(3)
      expect(reloaded_store.read_maximum_recommended_queue_size).to eq(25)
      expect(reloaded_store.read_enabled_seed_source_names).to eq(%w[current_playlist recent_tracks])
      expect(reloaded_store.read_seed_source_weights).to eq('current_playlist' => 4, 'recent_tracks' => 2)
      expect(reloaded_store.read_enabled_generator_names).to eq(%w[raw_seed track_similar])
      expect(reloaded_store.read_generator_weights).to eq('raw_seed' => 2, 'track_similar' => 3)
      expect(reloaded_store.read_exclude_explicit_recommendations).to be(true)
      expect(reloaded_store.read_replay_seed_before_recommendation).to be(true)
      expect(reloaded_store.read_seed_replay_interval).to eq(4)
    end
  end
end
