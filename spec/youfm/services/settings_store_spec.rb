# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::SettingsStore do
  it 'persists and reloads numeric settings' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'config.yml')
      store = described_class.new(path:)

      store.write_similar_artist_pool_limit(350)
      store.write_minimum_recommended_queue_size(3)
      store.write_exclude_explicit_recommendations(true)

      reloaded_store = described_class.new(path:)
      expect(reloaded_store.read_similar_artist_pool_limit).to eq(350)
      expect(reloaded_store.read_minimum_recommended_queue_size).to eq(3)
      expect(reloaded_store.read_exclude_explicit_recommendations).to be(true)
    end
  end
end
