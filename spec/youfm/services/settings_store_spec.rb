# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe YouFM::Services::SettingsStore do
  it 'persists and reloads the similar artist pool limit' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'config.yml')
      store = described_class.new(path:)

      store.write_similar_artist_pool_limit(350)

      reloaded_store = described_class.new(path:)
      expect(reloaded_store.read_similar_artist_pool_limit).to eq(350)
    end
  end
end
