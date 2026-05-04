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

      expect(client.get_similar_artists('Air', limit: 1).map(&:name)).to eq(['Phoenix'])
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

    it 'uses the cached prefix before topping up from the web' do
      cache_payload = Array.new(100) { |index| { 'name' => "Cached Artist #{index}", 'match' => '0.9' } }
      cache = instance_double(YouFM::Services::LastfmSimilarArtistsCache, fetch: cache_payload, save: true)
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        similar_artists_cache: cache
      )

      allow(client).to receive(:fetch_similar_artists_from_web).with('Air', limit: 150).and_return(
        Array.new(60) { |index| { 'name' => "Web Artist #{index}", 'match' => '0.4' } }
      )
      allow(client).to receive(:fetch_similar_artists_via_api).and_call_original

      result = client.get_similar_artists('Air', limit: 150)

      expect(result.length).to eq(150)
      expect(result.first(100).map(&:name)).to eq(Array.new(100) { |index| "Cached Artist #{index}" })
      expect(client).not_to have_received(:fetch_similar_artists_via_api)
      expect(cache).to have_received(:save).with(
        'Air',
        array_including({ 'name' => 'Web Artist 0', 'match' => '0.4' })
      )
    end

    it 'expands the similar artist pool via web pages when the requested limit exceeds the API cap' do
      cache = instance_double(YouFM::Services::LastfmSimilarArtistsCache, fetch: nil, save: true)
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        similar_artists_cache: cache
      )

      allow(client).to receive(:get).and_return(
        'similarartists' => {
          'artist' => Array.new(100) { |index| { 'name' => "API Artist #{index}", 'match' => '0.5' } }
        }
      )
      allow(client).to receive(:fetch_similar_artists_from_web).with('Air', limit: 150).and_return(
        Array.new(150) { |index| { 'name' => "Web Artist #{index}", 'match' => '0.4' } }
      )

      result = client.get_similar_artists('Air', limit: 150)

      expect(result.length).to eq(150)
      expect(result.first(100).map(&:name)).to eq(Array.new(100) { |index| "API Artist #{index}" })
      expect(result[100].name).to eq('Web Artist 0')
      expect(cache).to have_received(:save).with('Air', array_including({ 'name' => 'Web Artist 0', 'match' => '0.4' }))
    end
  end

  describe 'HTML similar artist parsing' do
    it 'extracts artist names from the similar artists page markup' do
      client = described_class.new(api_key: 'key', secret: 'secret')
      html = <<~HTML
        <section>
          <a class="link-block-target" href="/music/Air">Air</a>
          <a class="link-block-target" href="/music/Stereolab">Stereolab</a>
          <a class="link-block-target" href="/music/Broadcast">Broadcast</a>
        </section>
      HTML

      payload = client.send(:parse_similar_artists_from_html, html, artist_name: 'Air')

      expect(payload.map { |artist| artist['name'] }).to eq(%w[Stereolab Broadcast])
    end
  end
end
