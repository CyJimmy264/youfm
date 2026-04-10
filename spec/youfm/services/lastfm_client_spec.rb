# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::LastfmClient do
  describe '#get_similar_artists' do
    it 'returns cached similar artists without hitting the network' do
      cache = instance_double(
        YouFM::Services::LastfmSimilarArtistsCache,
        fetch: [{ 'name' => 'Phoenix', 'match' => '0.8' }]
      )
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        similar_artists_cache: cache
      )

      expect(client.get_similar_artists('Air').map(&:name)).to eq(['Phoenix'])
    end

    it 'fetches and caches similar artists on a cache miss' do
      cache = instance_double(YouFM::Services::LastfmSimilarArtistsCache, fetch: nil, save: true)
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        similar_artists_cache: cache
      )
      response = instance_double(
        Net::HTTPResponse,
        code: '200',
        body: JSON.dump('similarartists' => { 'artist' => [{ 'name' => 'Phoenix', 'match' => '0.8' }] })
      )

      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = client.get_similar_artists('Air')

      expect(result.map(&:name)).to eq(['Phoenix'])
      expect(cache).to have_received(:save).with('Air', [{ 'name' => 'Phoenix', 'match' => '0.8' }])
    end
  end
end
