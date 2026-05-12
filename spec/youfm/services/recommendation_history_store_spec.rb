# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::RecommendationHistoryStore do
  it 'persists and reloads fresh recommendation history ids' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'recommendation_history.yml')
      now = Time.utc(2026, 5, 12, 12, 0, 0)
      store = described_class.new(path:, clock: -> { now })

      store.remember('track-1')
      store.remember('track-2')

      expect(described_class.new(path:, clock: -> { now }).load).to eq(%w[track-1 track-2])
    end
  end

  it 'drops recommendation history entries older than ttl' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'recommendation_history.yml')
      saved_at = Time.utc(2026, 5, 11, 10, 0, 0)
      current_time = Time.utc(2026, 5, 12, 12, 0, 1)
      store = described_class.new(path:, clock: -> { saved_at })

      store.remember('track-1')

      expect(described_class.new(path:, clock: -> { current_time }).load).to eq([])
    end
  end
end
