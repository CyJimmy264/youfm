# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::LastfmClient do
  def http_client_with(*responses)
    instance_double(YouFM::Services::PersistentHttpClient).tap do |http_client|
      allow(http_client).to receive(:request).and_return(*responses)
    end
  end

  def http_response(code:, body:)
    instance_double(YouFM::Services::PersistentHttpClient::Response, code: code, body: body)
  end

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
      response = http_response(
        code: '200',
        body: JSON.dump('similarartists' => { 'artist' => [{ 'name' => 'Phoenix', 'match' => '0.8' }] })
      )
      http_client = http_client_with(response)
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        similar_artists_cache: cache,
        api_http_client: http_client
      )

      result = client.get_similar_artists('Air')

      expect(result.map(&:name)).to eq(['Phoenix'])
      expect(http_client).to have_received(:request)
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

  describe '#get_top_tracks' do
    it 'uses cached top tracks without hitting the network' do
      cache = instance_double(
        YouFM::Services::LastfmTopTracksCache,
        fetch: [{ 'name' => 'La femme d’argent', 'playcount' => '100', 'listeners' => '10' }]
      )
      client = described_class.new(api_key: 'key', secret: 'secret', top_tracks_cache: cache)

      result = client.get_top_tracks('Air', period: '12month', limit: 20)

      expect(result.map(&:name)).to eq(['La femme d’argent'])
      expect(cache).to have_received(:fetch).with('Air', period: '12month', limit: 20, ttl: 24 * 60 * 60)
    end

    it 'fetches and caches top tracks on a cache miss' do
      cache = instance_double(YouFM::Services::LastfmTopTracksCache, fetch: nil, save: true)
      tracks = [{ 'name' => 'La femme d’argent', 'playcount' => '100', 'listeners' => '10' }]
      response = http_response(code: '200', body: JSON.dump('toptracks' => { 'track' => tracks }))
      http_client = http_client_with(response)
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        top_tracks_cache: cache,
        api_http_client: http_client
      )

      result = client.get_top_tracks('Air', period: '12month', limit: 20)

      expect(result.map(&:name)).to eq(['La femme d’argent'])
      expect(cache).to have_received(:save).with('Air', period: '12month', limit: 20, tracks: tracks)
    end
  end

  describe 'session key resolution' do
    it 'uses the current session key from the provider for signed requests' do
      response = http_response(code: '200', body: JSON.dump('similarartists' => { 'artist' => [] }))
      http_client = http_client_with(response)
      token_store = instance_double(YouFM::Services::LastfmTokenStore)
      allow(token_store).to receive(:load).and_return({ 'key' => 'new-session-key' })
      client = described_class.new(
        api_key: 'key',
        secret: 'secret',
        session_key: 'stale-session-key',
        session_key_provider: -> { token_store.load['key'] },
        api_http_client: http_client
      )

      client.get_similar_artists('Air')

      expect(http_client).to have_received(:request).with(
        have_attributes(uri: have_attributes(query: include('sk=new-session-key')))
      )
    end
  end
end
