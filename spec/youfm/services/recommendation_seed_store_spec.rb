# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::RecommendationSeedStore do
  def store_path
    File.join(Dir.mktmpdir, 'recommendation_seeds.yml')
  end

  it 'persists and consumes a recommendation seed by track id' do
    path = store_path
    seed_label = 'The Great Undressing — Jenny Hval (Взят из плейлиста: Vibed)'

    described_class.new(path: path).save('track-1', seed_label, label: 'What’s Not Mine - Cate Le Bon')

    stored_payload = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
    expect(stored_payload['track-1']).to include(
      'label' => 'What’s Not Mine - Cate Le Bon',
      'seed_label' => seed_label
    )

    reloaded_store = described_class.new(path: path)
    expect(reloaded_store.fetch('track-1')).to eq(seed_label)
    expect(reloaded_store.fetch('track-1')).to be_nil
  end

  it 'does not return expired seeds' do
    now = Time.utc(2026, 5, 3, 10, 0, 0)
    path = store_path
    store = described_class.new(path: path, ttl: 24 * 60 * 60, clock: -> { now })

    store.save('track-1', 'Seed — Artist (Взят из плейлиста: Daily)')

    expired_store = described_class.new(path: path, ttl: 24 * 60 * 60, clock: -> { now + (25 * 60 * 60) })
    expect(expired_store.fetch('track-1')).to be_nil
  end
end
